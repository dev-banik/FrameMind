import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/utils/snackbar.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../../preview/presentation/widgets/download_dialog.dart';
import '../../../projects/data/models/project.dart';
import '../../../projects/providers/projects_providers.dart';
import '../../data/history_repository.dart';
import '../../data/models/chat_models.dart';
import '../../providers/chat_list_refresh.dart';
import '../../providers/history_providers.dart';

enum ChatAction { open, duplicate, download, move, delete }

/// Shared chat actions used by History, Home and Project detail.
abstract final class ChatActions {
  static void open(BuildContext context, String chatId) {
    context.push(AppRoutes.chat(chatId));
  }

  static Future<void> handle(
    BuildContext context,
    WidgetRef ref,
    ChatSummary chat,
    ChatAction action,
  ) async {
    switch (action) {
      case ChatAction.open:
        open(context, chat.id);
      case ChatAction.duplicate:
        await duplicate(context, ref, chat);
      case ChatAction.download:
        await download(context, chat);
      case ChatAction.move:
        await moveToProject(context, ref, chat);
      case ChatAction.delete:
        await delete(context, ref, chat);
    }
  }

  static Future<void> duplicate(
    BuildContext context,
    WidgetRef ref,
    ChatSummary chat,
  ) async {
    try {
      final copy = await ref.read(historyRepositoryProvider).duplicate(chat.id);
      refreshChatLists(ref.invalidate);
      showAppSnackBar(
        'Duplicated "${chat.displayTitle}"',
        actionLabel: 'Open',
        onAction: () {
          if (context.mounted) open(context, copy.id);
        },
      );
    } catch (e) {
      showAppSnackBar(friendlyError(e), isError: true);
    }
  }

  /// Returns true when the chat was deleted.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    ChatSummary chat, {
    bool confirm = true,
  }) async {
    if (confirm) {
      final ok = await showConfirmDialog(
        context,
        title: 'Delete this chat?',
        message:
            '"${chat.displayTitle}" and its scripts and videos will be permanently deleted.',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (!ok) return false;
    }
    try {
      await ref.read(historyRepositoryProvider).delete(chat.id);
      ref.read(historyControllerProvider.notifier).removeLocal(chat.id);
      refreshChatLists(ref.invalidate);
      showAppSnackBar('Chat deleted');
      return true;
    } catch (e) {
      showAppSnackBar(friendlyError(e), isError: true);
      return false;
    }
  }

  static Future<void> download(BuildContext context, ChatSummary chat) async {
    final videoId = chat.latestVideoId;
    if (videoId == null || videoId.isEmpty) {
      showAppSnackBar('This chat has no video yet.');
      return;
    }
    await showVideoDownloadDialog(context, videoId: videoId);
  }

  static Future<void> moveToProject(
    BuildContext context,
    WidgetRef ref,
    ChatSummary chat,
  ) async {
    final selection = await showModalBottomSheet<_ProjectChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _MoveToProjectSheet(currentProjectId: chat.projectId),
    );
    if (selection == null || !context.mounted) return;

    try {
      var projectId = selection.projectId;
      if (selection.createNew) {
        final name = await showTextInputDialog(
          context,
          title: 'New project',
          label: 'Project name',
          confirmLabel: 'Create',
        );
        if (name == null || !context.mounted) return;
        final project = await ref.read(projectsControllerProvider.notifier).create(name);
        projectId = project.id;
      }
      if (projectId == chat.projectId) return;
      await ref.read(historyRepositoryProvider).moveToProject(chat.id, projectId);
      ref.read(historyControllerProvider.notifier).replaceLocal(chat.copyWithProject(projectId));
      refreshChatLists(ref.invalidate);
      ref.invalidate(chatControllerProvider(chat.id));
      showAppSnackBar(projectId == null ? 'Removed from project' : 'Moved to project');
    } catch (e) {
      showAppSnackBar(friendlyError(e), isError: true);
    }
  }
}

/// Overflow menu with all chat actions.
class ChatActionsMenu extends ConsumerWidget {
  const ChatActionsMenu({super.key, required this.chat, this.onDeleted});

  final ChatSummary chat;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<ChatAction>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) async {
        if (action == ChatAction.delete) {
          final deleted = await ChatActions.delete(context, ref, chat);
          if (deleted) onDeleted?.call();
          return;
        }
        await ChatActions.handle(context, ref, chat, action);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: ChatAction.open,
          child: ListTile(leading: Icon(Icons.open_in_new_rounded), title: Text('Open')),
        ),
        const PopupMenuItem(
          value: ChatAction.duplicate,
          child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('Duplicate')),
        ),
        PopupMenuItem(
          value: ChatAction.download,
          enabled: chat.hasVideo,
          child: const ListTile(
            leading: Icon(Icons.download_rounded),
            title: Text('Download video'),
          ),
        ),
        const PopupMenuItem(
          value: ChatAction.move,
          child: ListTile(
            leading: Icon(Icons.drive_file_move_outline),
            title: Text('Move to project'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: ChatAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
            title: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ),
      ],
    );
  }
}

class _ProjectChoice {
  const _ProjectChoice({this.projectId, this.createNew = false});

  final String? projectId;
  final bool createNew;
}

class _MoveToProjectSheet extends ConsumerWidget {
  const _MoveToProjectSheet({required this.currentProjectId});

  final String? currentProjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsControllerProvider);
    final theme = Theme.of(context);

    Widget tile({
      required IconData icon,
      required String title,
      required _ProjectChoice choice,
      bool selected = false,
    }) {
      return ListTile(
        leading: Icon(icon),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: selected ? Icon(Icons.check_rounded, color: theme.colorScheme.primary) : null,
        onTap: () => Navigator.of(context).pop(choice),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Move to project', style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: projects.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(friendlyError(e)),
                ),
                data: (List<Project> list) => ListView(
                  shrinkWrap: true,
                  children: [
                    tile(
                      icon: Icons.add_rounded,
                      title: 'New project…',
                      choice: const _ProjectChoice(createNew: true),
                    ),
                    tile(
                      icon: Icons.folder_off_outlined,
                      title: 'No project',
                      choice: const _ProjectChoice(),
                      selected: currentProjectId == null,
                    ),
                    const Divider(),
                    for (final p in list)
                      tile(
                        icon: Icons.folder_outlined,
                        title: p.name,
                        choice: _ProjectChoice(projectId: p.id),
                        selected: p.id == currentProjectId,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
