import '../../../../core/models/enums.dart';
import '../../../../core/utils/json.dart';

class GeneratedVideo {
  const GeneratedVideo({
    required this.id,
    required this.chatId,
    required this.resolution,
    this.durationSeconds,
    this.thumbnailUrl,
    this.streamUrl,
    this.createdAt,
  });

  final String id;
  final String chatId;
  final Resolution resolution;
  final int? durationSeconds;
  final String? thumbnailUrl;

  /// Signed URL; it expires, so reload the chat to refresh it.
  final String? streamUrl;
  final DateTime? createdAt;

  factory GeneratedVideo.fromJson(Map<String, dynamic> json) => GeneratedVideo(
        id: asString(json['id']),
        chatId: asString(json['chatId']),
        resolution: Resolution.parse(json['resolution']),
        durationSeconds: asIntOrNull(json['durationSeconds']),
        thumbnailUrl: asStringOrNull(json['thumbnailUrl']),
        streamUrl: asStringOrNull(json['streamUrl']),
        createdAt: asDateOrNull(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'resolution': resolution.apiValue,
        'durationSeconds': durationSeconds,
        'thumbnailUrl': thumbnailUrl,
        'streamUrl': streamUrl,
        'createdAt': dateToJson(createdAt),
      };
}

class GenerationJob {
  const GenerationJob({
    required this.id,
    required this.chatId,
    required this.stage,
    this.progress = 0,
    this.error,
    this.videoId,
    this.createdAt,
    this.completedAt,
  });

  final String id;
  final String chatId;
  final GenerationStage stage;

  /// 0-100.
  final int progress;
  final String? error;
  final String? videoId;
  final DateTime? createdAt;
  final DateTime? completedAt;

  bool get isTerminal => stage.isTerminal;
  bool get isComplete => stage == GenerationStage.complete;
  bool get isFailed => stage == GenerationStage.failed;

  double get fraction => (progress.clamp(0, 100)) / 100.0;

  factory GenerationJob.fromJson(Map<String, dynamic> json) => GenerationJob(
        id: asString(json['id']),
        chatId: asString(json['chatId']),
        stage: GenerationStage.parse(json['stage']),
        progress: asInt(json['progress']),
        error: asStringOrNull(json['error']),
        videoId: asStringOrNull(json['videoId']),
        createdAt: asDateOrNull(json['createdAt']),
        completedAt: asDateOrNull(json['completedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'stage': stage.apiValue,
        'progress': progress,
        'error': error,
        'videoId': videoId,
        'createdAt': dateToJson(createdAt),
        'completedAt': dateToJson(completedAt),
      };
}

/// Response of `GET /video/{videoId}/download`.
class DownloadInfo {
  const DownloadInfo({required this.url, required this.fileName, this.expiresAt});

  final String url;
  final String fileName;
  final DateTime? expiresAt;

  factory DownloadInfo.fromJson(Map<String, dynamic> json) => DownloadInfo(
        url: asString(json['url']),
        fileName: asString(json['fileName']),
        expiresAt: asDateOrNull(json['expiresAt']),
      );
}
