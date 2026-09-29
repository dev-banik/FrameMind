import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/snackbar.dart';
import '../../providers/video_download_controller.dart';

/// Downloads a video and saves it to the gallery, showing progress in a
/// dialog. Used from lists where there's no inline player.
Future<void> showVideoDownloadDialog(BuildContext context, {required String videoId}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DownloadDialog(videoId: videoId),
  );
}

class _DownloadDialog extends ConsumerStatefulWidget {
  const _DownloadDialog({required this.videoId});

  final String videoId;

  @override
  ConsumerState<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends ConsumerState<_DownloadDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final ok = await ref
        .read(videoDownloadControllerProvider(widget.videoId).notifier)
        .saveToGallery();
    if (ok && mounted) {
      Navigator.of(context).pop();
      showAppSnackBar('Saved to gallery');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoDownloadControllerProvider(widget.videoId));
    final theme = Theme.of(context);
    final failed = state.phase == DownloadPhase.failed;

    return AlertDialog(
      title: Text(failed ? 'Download failed' : 'Saving video'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed)
            Text(friendlyError(state.error))
          else ...[
            Text(
              state.phase == DownloadPhase.saving
                  ? 'Saving to your gallery…'
                  : 'Downloading… ${(state.progress * 100).round()}%',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: state.phase == DownloadPhase.saving || state.progress <= 0
                  ? null
                  : state.progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ],
      ),
      actions: [
        if (failed && state.permissionDenied)
          TextButton(
            onPressed: openAppSettings,
            child: const Text('Open settings'),
          ),
        if (failed)
          TextButton(
            onPressed: _start,
            child: const Text('Retry'),
          ),
        TextButton(
          onPressed: () {
            ref.read(videoDownloadControllerProvider(widget.videoId).notifier).cancel();
            Navigator.of(context).pop();
          },
          child: Text(failed ? 'Close' : 'Cancel'),
        ),
      ],
    );
  }
}
