import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/state_views.dart';
import '../../history/data/models/chat_models.dart';
import '../../history/providers/chat_list_refresh.dart';
import '../../history/providers/history_providers.dart';
import '../providers/script_editor_controller.dart';
import 'widgets/resolution_sheet.dart';
import 'widgets/scene_card.dart';

class ScriptScreen extends ConsumerWidget {
  const ScriptScreen({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(scriptEditorProvider(chatId));
    final chat = ref.watch(chatControllerProvider(chatId)).valueOrNull;
    final editorState = editor.valueOrNull;
    final busy = editorState?.isBusy ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your script'),
        actions: [
          if (editorState != null)
            IconButton(
              tooltip: 'Regenerate script',
              onPressed: busy ? null : () => _regenerateAll(context, ref),
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (editorState != null)
            PopupMenuButton<String>(
              enabled: !busy,
              onSelected: (value) async {
                if (value == 'discard') {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Discard local changes?',
                    message: 'Your unsaved edits will be replaced with the last saved script.',
                    confirmLabel: 'Discard',
                    destructive: true,
                  );
                  if (ok) {
                    await ref.read(scriptEditorProvider(chatId).notifier).discardLocalChanges();
                  }
                } else if (value == 'config') {
                  if (context.mounted) context.push(AppRoutes.config(chatId));
                } else if (value == 'videos') {
                  if (context.mounted) context.push(AppRoutes.preview(chatId));
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'config',
                  child: ListTile(
                    leading: Icon(Icons.tune_rounded),
                    title: Text('Change settings'),
                  ),
                ),
                if (chat != null && chat.videos.isNotEmpty)
                  const PopupMenuItem(
                    value: 'videos',
                    child: ListTile(
                      leading: Icon(Icons.video_library_outlined),
                      title: Text('View videos'),
                    ),
                  ),
                PopupMenuItem(
                  value: 'discard',
                  enabled: editorState.dirty,
                  child: const ListTile(
                    leading: Icon(Icons.restore_rounded),
                    title: Text('Discard local changes'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: editor.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingView(message: 'Loading script…'),
        error: (error, _) {
          if (error is ScriptMissingException) {
            return EmptyView(
              icon: Icons.edit_note_rounded,
              title: 'No script yet',
              message: 'Choose language, duration, style and voice to write one.',
              action: FilledButton(
                onPressed: () => context.pushReplacement(AppRoutes.config(chatId)),
                child: const Text('Configure script'),
              ),
            );
          }
          return ErrorView(
            error: error,
            onRetry: () => ref.invalidate(chatControllerProvider(chatId)),
          );
        },
        data: (state) => _ScriptEditorBody(chatId: chatId, state: state, chat: chat),
      ),
      bottomNavigationBar: editorState == null
          ? null
          : _BottomActions(
              state: editorState,
              onSave: () => _save(context, ref),
              onGenerate: () => _generateVideo(context, ref),
            ),
    );
  }

  void _showError(BuildContext context, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(friendlyError(error)),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(scriptEditorProvider(chatId).notifier).saveDraft();
      refreshChatLists(ref.invalidate);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved')),
        );
      }
    } catch (e) {
      _showError(context, e);
    }
  }

  Future<void> _regenerateAll(BuildContext context, WidgetRef ref) async {
    final instructions = await showTextInputDialog(
      context,
      title: 'Regenerate script',
      label: 'Instructions (optional)',
      hint: 'e.g. Make it funnier and add a twist at the end',
      confirmLabel: 'Regenerate',
      maxLength: 300,
      maxLines: 3,
      allowEmpty: true,
    );
    if (instructions == null) return;
    try {
      await ref
          .read(scriptEditorProvider(chatId).notifier)
          .regenerateAll(instructions: instructions);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _generateVideo(BuildContext context, WidgetRef ref) async {
    final resolution = await showResolutionSheet(context);
    if (resolution == null) return;
    try {
      final job = await ref.read(scriptEditorProvider(chatId).notifier).startVideo(resolution);
      await ref.read(appPreferencesProvider).setLastResolution(resolution.apiValue);
      refreshChatListsAndQuota(ref.invalidate);
      if (!context.mounted) return;
      context.push(AppRoutes.generation(chatId, jobId: job.id, resolution: resolution));
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }
}

class _ScriptEditorBody extends ConsumerWidget {
  const _ScriptEditorBody({required this.chatId, required this.state, required this.chat});

  final String chatId;
  final ScriptEditorState state;
  final Chat? chat;

  ScriptEditorController _controller(WidgetRef ref) =>
      ref.read(scriptEditorProvider(chatId).notifier);

  Future<void> _onSceneMenu(
    BuildContext context,
    WidgetRef ref,
    EditableScene item,
    int index,
    SceneMenuAction action,
  ) async {
    final controller = _controller(ref);
    switch (action) {
      case SceneMenuAction.regenerate:
        final instructions = await showTextInputDialog(
          context,
          title: 'Regenerate scene ${index + 1}',
          label: 'Instructions (optional)',
          hint: 'e.g. Make it more emotional',
          confirmLabel: 'Regenerate',
          maxLength: 300,
          maxLines: 3,
          allowEmpty: true,
        );
        if (instructions == null) return;
        try {
          await controller.regenerateScene(item.id, instructions: instructions);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(friendlyError(e)),
              backgroundColor: Theme.of(context).colorScheme.error,
            ));
          }
        }
      case SceneMenuAction.moveUp:
        controller.moveScene(item.id, -1);
      case SceneMenuAction.moveDown:
        controller.moveScene(item.id, 1);
      case SceneMenuAction.delete:
        final ok = await showConfirmDialog(
          context,
          title: 'Delete scene ${index + 1}?',
          message: 'This scene will be removed from your script.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok) controller.deleteScene(item.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = _controller(ref);
    final characterNames = state.characters.map((c) => c.name).where((n) => n.isNotEmpty).toList();
    final regeneratingAll = state.busy == ScriptBusy.regeneratingAll;
    final editable = !state.isBusy;
    final failed = chat?.status == ChatStatus.failed;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (failed) ...[
              InfoBanner(
                isError: true,
                icon: Icons.error_outline_rounded,
                message: chat?.activeJob?.error?.isNotEmpty == true
                    ? 'Video generation failed: ${chat!.activeJob!.error}'
                    : 'The last video generation failed. Review your script and try again.',
              ),
              const SizedBox(height: 12),
            ],
            if (state.restoredFromDraft && state.dirty) ...[
              const InfoBanner(
                icon: Icons.history_rounded,
                message: 'Restored your unsaved edits from this device.',
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              key: ValueKey('title-${state.revision}'),
              initialValue: state.title,
              enabled: editable,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: controller.setTitle,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('summary-${state.revision}'),
              initialValue: state.summary,
              enabled: editable,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Summary',
                alignLabelWithHint: true,
              ),
              onChanged: controller.setSummary,
            ),
            if (state.characters.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Characters', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in state.characters)
                    Tooltip(
                      message: c.description,
                      child: Chip(
                        avatar: const Icon(Icons.person_rounded, size: 18),
                        label: Text(c.name),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Scenes (${state.scenes.length})',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Icon(Icons.timer_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  formatClock(Duration(seconds: state.totalDurationSeconds)),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.scenes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No scenes yet - add one below.')),
              ),
            for (var i = 0; i < state.scenes.length; i++)
              Padding(
                key: ValueKey('scene-${state.scenes[i].id}'),
                padding: const EdgeInsets.only(bottom: 14),
                child: SceneCard(
                  item: state.scenes[i],
                  index: i,
                  total: state.scenes.length,
                  enabled: editable,
                  regenerating: state.busy == ScriptBusy.regeneratingScene &&
                      state.busySceneId == state.scenes[i].id,
                  characterNames: characterNames,
                  onChanged: (change) => controller.updateScene(state.scenes[i].id, change),
                  onAddDialogue: () => controller.addDialogue(state.scenes[i].id),
                  onUpdateDialogue: (index, d) =>
                      controller.updateDialogue(state.scenes[i].id, index, d),
                  onRemoveDialogue: (index) =>
                      controller.removeDialogue(state.scenes[i].id, index),
                  onPickCharacter: (index, name) =>
                      controller.setDialogueCharacter(state.scenes[i].id, index, name),
                  onMenu: (action) =>
                      _onSceneMenu(context, ref, state.scenes[i], i, action),
                ),
              ),
            OutlinedButton.icon(
              onPressed: editable ? controller.addScene : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add scene'),
            ),
          ],
        ),
        if (regeneratingAll)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surface.withAlpha(200),
              child: const LoadingView(message: 'Writing a fresh script…'),
            ),
          ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.state,
    required this.onSave,
    required this.onGenerate,
  });

  final ScriptEditorState state;
  final VoidCallback onSave;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saving = state.busy == ScriptBusy.saving;
    final starting = state.busy == ScriptBusy.startingVideo;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.dirty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Unsaved changes (kept on this device)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isBusy ? null : onSave,
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save Draft'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: state.isBusy || state.scenes.isEmpty ? null : onGenerate,
                    icon: starting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.movie_creation_rounded),
                    label: const Text('Generate Video'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
