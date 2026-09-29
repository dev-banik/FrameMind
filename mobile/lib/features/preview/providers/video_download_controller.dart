import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/video_download_service.dart';

enum DownloadPhase { idle, downloading, saving, saved, failed }

class DownloadState {
  const DownloadState({
    this.phase = DownloadPhase.idle,
    this.progress = 0,
    this.filePath,
    this.error,
  });

  final DownloadPhase phase;

  /// 0..1 while downloading.
  final double progress;

  /// Local file once downloaded (reused for sharing).
  final String? filePath;
  final Object? error;

  bool get isWorking =>
      phase == DownloadPhase.downloading || phase == DownloadPhase.saving;

  bool get permissionDenied => error is GalleryPermissionException;

  DownloadState copyWith({
    DownloadPhase? phase,
    double? progress,
    String? filePath,
    Object? Function()? error,
  }) =>
      DownloadState(
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        filePath: filePath ?? this.filePath,
        error: error != null ? error() : this.error,
      );
}

/// Per-video download state (keyed by video id).
class VideoDownloadController extends AutoDisposeFamilyNotifier<DownloadState, String> {
  CancelToken? _cancelToken;

  @override
  DownloadState build(String arg) {
    ref.onDispose(() => _cancelToken?.cancel('disposed'));
    return const DownloadState();
  }

  VideoDownloadService get _service => ref.read(videoDownloadServiceProvider);

  /// Downloads (if needed) and returns the local file path, or null on error.
  Future<String?> ensureDownloaded() async {
    final existing = state.filePath;
    if (existing != null) return existing;
    if (state.isWorking) return null;

    _cancelToken = CancelToken();
    state = state.copyWith(
      phase: DownloadPhase.downloading,
      progress: 0,
      error: () => null,
    );
    try {
      var lastReported = 0.0;
      final file = await _service.download(
        arg,
        cancelToken: _cancelToken,
        onProgress: (p) {
          // Throttle rebuilds to ~1% steps.
          if (p - lastReported >= 0.01 || p >= 1) {
            lastReported = p;
            state = state.copyWith(progress: p);
          }
        },
      );
      state = state.copyWith(
        phase: DownloadPhase.idle,
        progress: 1,
        filePath: file.path,
      );
      return file.path;
    } catch (e) {
      if (e is ApiException && e.isCancelled) {
        state = const DownloadState();
        return null;
      }
      state = state.copyWith(phase: DownloadPhase.failed, error: () => e);
      return null;
    }
  }

  /// Downloads and saves the video into the "FrameMind" gallery album.
  /// Returns true on success; on failure [DownloadState.error] is set.
  Future<bool> saveToGallery() async {
    if (state.isWorking) return false;
    final path = await ensureDownloaded();
    if (path == null) return false;
    state = state.copyWith(phase: DownloadPhase.saving, error: () => null);
    try {
      await _service.saveToGallery(path);
      state = state.copyWith(phase: DownloadPhase.saved);
      return true;
    } catch (e) {
      state = state.copyWith(phase: DownloadPhase.failed, error: () => e);
      return false;
    }
  }

  void cancel() {
    _cancelToken?.cancel('cancelled by user');
  }
}

final videoDownloadControllerProvider = NotifierProvider.autoDispose
    .family<VideoDownloadController, DownloadState, String>(
  VideoDownloadController.new,
);
