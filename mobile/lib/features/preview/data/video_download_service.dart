import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../generation/data/generation_repository.dart';

class GalleryPermissionException extends AppException {
  const GalleryPermissionException()
      : super('FrameMind needs permission to save videos to your gallery.');
}

class GallerySaveException extends AppException {
  const GallerySaveException(super.message);
}

/// Downloads generated MP4s from signed URLs and saves them to the gallery.
class VideoDownloadService {
  VideoDownloadService(this._generationRepo, this._dio);

  final GenerationRepository _generationRepo;
  final Dio _dio;

  /// Downloads the video to the temp directory (reusing a previous download)
  /// and returns the local file.
  Future<File> download(
    String videoId, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}framemind_videos');
    if (!await folder.exists()) await folder.create(recursive: true);

    // Reuse an earlier download of the same video.
    final existing = folder
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('${videoId}_') &&
            f.path.endsWith('.mp4'));
    for (final file in existing) {
      if (await file.length() > 0) {
        onProgress?.call(1);
        return file;
      }
    }

    final info = await _generationRepo.getDownloadInfo(videoId);
    if (info.url.isEmpty) {
      throw const AppException('The download link is not available yet.');
    }
    final fileName = _safeFileName(info.fileName, videoId);
    final target = File('${folder.path}${Platform.pathSeparator}${videoId}_$fileName');
    final partial = File('${target.path}.part');

    try {
      await _dio.download(
        info.url,
        partial.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
    } on DioException catch (e) {
      if (await partial.exists()) await partial.delete();
      throw ApiException.fromDio(e);
    }
    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
    onProgress?.call(1);
    return target;
  }

  /// Saves a local MP4 into the "FrameMind" album (Android: Movies/FrameMind,
  /// iOS: Photos album).
  Future<void> saveToGallery(String path) async {
    var hasAccess = await Gal.hasAccess(toAlbum: true);
    if (!hasAccess) {
      hasAccess = await Gal.requestAccess(toAlbum: true);
    }
    if (!hasAccess) throw const GalleryPermissionException();

    try {
      await Gal.putVideo(path, album: AppConfig.galleryAlbum);
    } on GalException catch (e) {
      if (e.type == GalExceptionType.accessDenied) {
        throw const GalleryPermissionException();
      }
      if (e.type == GalExceptionType.notEnoughSpace) {
        throw const GallerySaveException('Not enough storage space to save the video.');
      }
      if (e.type == GalExceptionType.notSupportedFormat) {
        throw const GallerySaveException('This video format is not supported by your gallery.');
      }
      throw const GallerySaveException('Could not save the video to your gallery.');
    }
  }

  static String _safeFileName(String name, String videoId) {
    var cleaned = name.trim().replaceAll(RegExp(r'[^\w\-. ]'), '_');
    if (cleaned.isEmpty) cleaned = 'framemind_$videoId';
    if (cleaned.length > 80) cleaned = cleaned.substring(0, 80);
    if (!cleaned.toLowerCase().endsWith('.mp4')) cleaned = '$cleaned.mp4';
    return cleaned;
  }
}

final videoDownloadServiceProvider = Provider<VideoDownloadService>(
  (ref) => VideoDownloadService(
    ref.watch(generationRepositoryProvider),
    ref.watch(downloadDioProvider),
  ),
);
