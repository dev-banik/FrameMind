import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/state_views.dart';
import '../../history/data/models/chat_models.dart';
import '../../history/providers/chat_list_refresh.dart';
import '../../history/providers/history_providers.dart';
import '../data/script_repository.dart';
import '../providers/script_config_provider.dart';

/// Language / Duration / Style / Voice selection before generating a script.
class ScriptConfigScreen extends ConsumerWidget {
  const ScriptConfigScreen({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider(chatId));
    return Scaffold(
      appBar: AppBar(title: const Text('Script settings')),
      body: AsyncValueView(
        value: chat,
        onRetry: () => ref.invalidate(chatControllerProvider(chatId)),
        data: (chat) => _ConfigForm(chat: chat),
      ),
    );
  }
}

class _ConfigForm extends ConsumerStatefulWidget {
  const _ConfigForm({required this.chat});

  final Chat chat;

  @override
  ConsumerState<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends ConsumerState<_ConfigForm> {
  final _formKey = GlobalKey<FormState>();
  late Language _language;
  late VideoStyle _style;
  late VoiceType _voice;

  /// Selected preset, or null for "Custom".
  int? _preset;
  late final TextEditingController _customController;
  late final TextEditingController _promptController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final last = ref.read(lastScriptConfigProvider);
    final chat = widget.chat;
    // Prefer values already stored on the chat (e.g. when re-configuring),
    // otherwise the user's last choices.
    _language = chat.language ?? last.language;
    _style = chat.style ?? last.style;
    _voice = chat.voiceType ?? last.voice;
    final duration = chat.durationSeconds ?? last.durationSeconds;
    _preset = kPresetDurations.contains(duration) ? duration : null;
    _customController = TextEditingController(text: duration.toString());
    _promptController = TextEditingController(text: chat.userPrompt ?? '');
  }

  @override
  void dispose() {
    _customController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  int get _durationSeconds =>
      _preset ?? int.tryParse(_customController.text.trim()) ?? 60;

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);

    final config = ScriptConfig(
      language: _language,
      durationSeconds: _durationSeconds,
      style: _style,
      voice: _voice,
    );
    try {
      await ref.read(lastScriptConfigProvider.notifier).remember(config);
      final chat = await ref.read(scriptRepositoryProvider).generate(
            chatId: widget.chat.id,
            language: config.language,
            durationSeconds: config.durationSeconds,
            style: config.style,
            voiceType: config.voice,
            userPrompt: _promptController.text,
          );
      // A fresh script replaces any stale local draft.
      await ref.read(scriptRepositoryProvider).clearLocalDraft(chat.id);
      ref.read(chatControllerProvider(widget.chat.id).notifier).setChat(chat);
      refreshChatLists(ref.invalidate);
      if (!mounted) return;
      context.pushReplacement(AppRoutes.script(chat.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Text(
                widget.chat.analysis?.sourceTitle.isNotEmpty == true
                    ? 'Inspired by "${widget.chat.analysis!.sourceTitle}"'
                    : 'Configure your original script',
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose how your new video should sound and look.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (widget.chat.analysis != null)
                    TextButton(
                      onPressed: () => context.push(AppRoutes.analysis(widget.chat.id)),
                      child: const Text('View analysis'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<Language>(
                value: _language,
                decoration: const InputDecoration(
                  labelText: 'Language',
                  prefixIcon: Icon(Icons.translate_rounded),
                ),
                items: [
                  for (final l in Language.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
                onChanged: _submitting ? null : (v) => setState(() => _language = v ?? _language),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                value: _preset,
                decoration: const InputDecoration(
                  labelText: 'Duration',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
                items: [
                  for (final d in kPresetDurations)
                    DropdownMenuItem<int?>(value: d, child: Text('$d seconds')),
                  const DropdownMenuItem<int?>(value: null, child: Text('Custom…')),
                ],
                onChanged: _submitting ? null : (v) => setState(() => _preset = v),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _preset == null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: _customController,
                          enabled: !_submitting,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Custom duration (seconds)',
                            helperText:
                                'Between ${AppConfig.minDurationSeconds} and ${AppConfig.maxDurationSeconds} seconds',
                            suffixText: 'sec',
                          ),
                          validator: (value) {
                            if (_preset != null) return null;
                            final n = int.tryParse(value?.trim() ?? '');
                            if (n == null) return 'Enter a number of seconds';
                            if (n < AppConfig.minDurationSeconds ||
                                n > AppConfig.maxDurationSeconds) {
                              return 'Must be ${AppConfig.minDurationSeconds}-${AppConfig.maxDurationSeconds} seconds';
                            }
                            return null;
                          },
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<VideoStyle>(
                value: _style,
                decoration: const InputDecoration(
                  labelText: 'Style',
                  prefixIcon: Icon(Icons.palette_outlined),
                ),
                items: [
                  for (final s in VideoStyle.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: _submitting ? null : (v) => setState(() => _style = v ?? _style),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<VoiceType>(
                value: _voice,
                decoration: const InputDecoration(
                  labelText: 'Voice',
                  prefixIcon: Icon(Icons.record_voice_over_outlined),
                ),
                items: [
                  for (final v in VoiceType.values)
                    DropdownMenuItem(value: v, child: Text(v.label)),
                ],
                onChanged: _submitting ? null : (v) => setState(() => _voice = v ?? _voice),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _promptController,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Extra direction (optional)',
                  hintText: 'Anything the story should include or avoid',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 8,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _submitting ? null : _generate,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.edit_note_rounded),
                    label: Text(_submitting ? 'Writing your script…' : 'Generate Script'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
