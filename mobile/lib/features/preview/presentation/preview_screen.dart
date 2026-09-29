import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/network_thumbnail.dart';
import '../../../core/widgets/state_views.dart';
import '../../generation/data/generation_repository.dart';
import '../../generation/data/models/generation_models.dart';
import '../../history/data/models/chat_models.dart';
import '../../history/providers/chat_list_refresh.dart';
import '../../history/providers/history_providers.dart';
import '../../script/presentation/widgets/resolution_sheet.dart';
import '../providers/video_download_controller.dart';
import 'widgets/video_player_view.dart';

class PreviewScreen extends ConsumerStatefulWidget {
  const PreviewScreen({super.key, required this.chatId, this.videoId});

  final String chatId;
  final String? videoId;

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> {
  String? _selectedVideoId;

  @override
  void initState() {
    super.initState();
    _selectedVideoId = widget.videoId;
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatControllerProvider(widget.chatId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your video'),
        actions: [
          IconButton(
            tooltip: 'Open script',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => context.push(AppRoutes.script(widget.chatId)),
          ),
        ],
      ),
      body: AsyncValueView(
        value: chatAsync,
        onRetry: () => ref.invalidate(chatControllerProvider(widget.chatId)),
        data: (chat) {
          final videos = chat.videosNewestFirst;
          if (videos.isEmpty) return _NoVideos(chat: chat);
          final selected = videos.firstWhere(
            (v) => v.id == _selectedVideoId,
            orElse: () => videos.first,
          );
          return RefreshIndicator(
            onRefresh: () => ref.read(chatControllerProvider(widget.chatId).notifier).reload(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (selected.streamUrl != null && selected.streamUrl!.isNotEmpty)
                  VideoPlayerView(
                    key: ValueKey('player-${selected.id}'),
                    url: selected.streamUrl!,
                    onLoadError: () =>
                        ref.read(chatControllerProvider(widget.chatId).notifier).reload(),
                  )
                else
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: NetworkThumbnail(url: selected.thumbnailUrl, borderRadius: 0),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _VideoInfo(chat: chat, video: selected),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _ActionRow(chat: chat, video: selected),
                ),
                if (videos.length > 1) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                    child: Text(
                      'All versions (${videos.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  for (final v in videos)
                    ListTile(
                      selected: v.id == selected.id,
                      leading: NetworkThumbnail(
                        url: v.thumbnailUrl,
                        width: 72,
                        height: 44,
                        borderRadius: 8,
                      ),
                      title: Text('${v.resolution.label} · ${formatDurationShort(v.durationSeconds)}'),
                      subtitle: Text(formatDateTime(v.createdAt)),
                      trailing: v.id == selected.id
                          ? const Icon(Icons.play_circle_fill_rounded)
                          : null,
                      onTap: () => setState(() => _selectedVideoId = v.id),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VideoInfo extends StatelessWidget {
  const _VideoInfo({required this.chat, required this.video});

  final Chat chat;
  final GeneratedVideo video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      video.resolution.label,
      if (video.durationSeconds != null) formatDurationShort(video.durationSeconds),
      if (chat.language != null) chat.language!.apiValue,
      if (chat.style != null) chat.style!.label,
      if (video.createdAt != null) formatDate(video.createdAt),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          chat.displayTitle,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          meta.join(' · '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.chat, required this.video});

  final Chat chat;
  final GeneratedVideo video;

  void _snack(BuildContext context, String message, {bool error = false, SnackBarAction? action}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        action: action,
      ));
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(videoDownloadControllerProvider(video.id).notifier);
    final ok = await controller.saveToGallery();
    if (!context.mounted) return;
    if (ok) {
      _snack(context, 'Saved to gallery');
      return;
    }
    final state = ref.read(videoDownloadControllerProvider(video.id));
    if (state.error == null) return; // cancelled
    _snack(
      context,
      friendlyError(state.error),
      error: true,
      action: state.permissionDenied
          ? SnackBarAction(
              label: 'Settings',
              textColor: Theme.of(context).colorScheme.onError,
              onPressed: openAppSettings,
            )
          : null,
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final path =
        await ref.read(videoDownloadControllerProvider(video.id).notifier).ensureDownloaded();
    if (!context.mounted) return;
    if (path == null) {
      final error = ref.read(videoDownloadControllerProvider(video.id)).error;
      if (error != null) _snack(context, friendlyError(error), error: true);
      return;
    }
    try {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'video/mp4')],
        text: '${chat.displayTitle} - made with FrameMind',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (context.mounted) _snack(context, 'Sharing failed. Please try again.', error: true);
    }
  }

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Edit script first'),
              subtitle: const Text('Tweak scenes, then generate a new version'),
              onTap: () => Navigator.of(context).pop('script'),
            ),
            ListTile(
              leading: const Icon(Icons.replay_rounded),
              title: const Text('Generate again'),
              subtitle: const Text('Render a new version of the same script'),
              onTap: () => Navigator.of(context).pop('again'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'script') {
      context.push(AppRoutes.script(chat.id));
      return;
    }

    final resolution = await showResolutionSheet(context);
    if (resolution == null || !context.mounted) return;
    try {
      final job = await ref
          .read(generationRepositoryProvider)
          .generate(chatId: chat.id, resolution: resolution);
      await ref.read(appPreferencesProvider).setLastResolution(resolution.apiValue);
      refreshChatListsAndQuota(ref.invalidate);
      if (!context.mounted) return;
      context.pushReplacement(
        AppRoutes.generation(chat.id, jobId: job.id, resolution: resolution),
      );
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final download = ref.watch(videoDownloadControllerProvider(video.id));
    final working = download.isWorking;

    final downloadLabel = switch (download.phase) {
      DownloadPhase.downloading => '${(download.progress * 100).round()}%',
      DownloadPhase.saving => 'Saving…',
      DownloadPhase.saved => 'Saved',
      _ => 'Download',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: working ? null : () => _download(context, ref),
          icon: working
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: download.phase == DownloadPhase.downloading && download.progress > 0
                        ? download.progress
                        : null,
                  ),
                )
              : Icon(download.phase == DownloadPhase.saved
                  ? Icons.check_circle_rounded
                  : Icons.download_rounded),
          label: Text(downloadLabel),
        ),
        if (working && download.phase == DownloadPhase.downloading) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: download.progress > 0 ? download.progress : null,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(videoDownloadControllerProvider(video.id).notifier).cancel(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Builder(
                builder: (buttonContext) => OutlinedButton.icon(
                  onPressed: working ? null : () => _share(buttonContext, ref),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: working ? null : () => _regenerate(context, ref),
                icon: const Icon(Icons.autorenew_rounded),
                label: const Text('Regenerate'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoVideos extends StatelessWidget {
  const _NoVideos({required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    if (chat.status.isInProgress) {
      return EmptyView(
        icon: Icons.hourglass_top_rounded,
        title: 'Your video is still being made',
        message: "We'll notify you when it's ready.",
        action: FilledButton(
          onPressed: () => context.pushReplacement(
            AppRoutes.generation(chat.id, jobId: chat.activeJob?.id),
          ),
          child: const Text('View progress'),
        ),
      );
    }
    return EmptyView(
      icon: Icons.movie_filter_outlined,
      title: 'No videos yet',
      message: 'Generate a video from your script to see it here.',
      action: FilledButton(
        onPressed: () => context.pushReplacement(AppRoutes.script(chat.id)),
        child: const Text('Open script'),
      ),
    );
  }
}
