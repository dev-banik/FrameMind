import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/state_views.dart';
import '../data/models/chat_models.dart';
import '../providers/history_providers.dart';

/// Where to go when a chat is opened, based on its status:
/// Analyzed → config, ScriptReady → script, Queued/Generating → progress,
/// Completed → preview, Failed → script (with error banner).
String routeForChat(Chat chat) {
  return switch (chat.status) {
    ChatStatus.analyzed => AppRoutes.config(chat.id),
    ChatStatus.scriptReady => AppRoutes.script(chat.id),
    ChatStatus.failed => AppRoutes.script(chat.id),
    ChatStatus.queued || ChatStatus.generating =>
      AppRoutes.generation(chat.id, jobId: chat.activeJob?.id),
    ChatStatus.completed => AppRoutes.preview(chat.id),
    ChatStatus.unknown =>
      chat.script != null ? AppRoutes.script(chat.id) : AppRoutes.config(chat.id),
  };
}

/// Loads a chat and forwards to the right screen for its status.
class ChatEntryScreen extends ConsumerStatefulWidget {
  const ChatEntryScreen({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ChatEntryScreen> createState() => _ChatEntryScreenState();
}

class _ChatEntryScreenState extends ConsumerState<ChatEntryScreen> {
  bool _forwarded = false;

  void _forward(Chat chat) {
    if (_forwarded) return;
    _forwarded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pushReplacement(routeForChat(chat));
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider(widget.chatId));
    return Scaffold(
      appBar: AppBar(),
      body: chat.when(
        loading: () => const LoadingView(message: 'Opening…'),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(chatControllerProvider(widget.chatId)),
        ),
        data: (chat) {
          _forward(chat);
          return const LoadingView(message: 'Opening…');
        },
      ),
    );
  }
}
