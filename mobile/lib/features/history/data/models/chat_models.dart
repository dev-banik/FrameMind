import '../../../../core/models/enums.dart';
import '../../../../core/utils/json.dart';
import '../../../analysis/data/models/video_analysis.dart';
import '../../../generation/data/models/generation_models.dart';
import '../../../script/data/models/script.dart';

/// History list item.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    required this.status,
    this.projectId,
    this.thumbnailUrl,
    this.language,
    this.durationSeconds,
    this.latestVideoId,
    this.createdAt,
  });

  final String id;
  final String? projectId;
  final String title;
  final String? thumbnailUrl;
  final Language? language;
  final int? durationSeconds;
  final ChatStatus status;
  final String? latestVideoId;
  final DateTime? createdAt;

  bool get hasVideo => latestVideoId != null && latestVideoId!.isNotEmpty;

  String get displayTitle => title.trim().isEmpty ? 'Untitled idea' : title;

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
        id: asString(json['id']),
        projectId: asStringOrNull(json['projectId']),
        title: asString(json['title']),
        thumbnailUrl: asStringOrNull(json['thumbnailUrl']),
        language: Language.tryParse(json['language']),
        durationSeconds: asIntOrNull(json['durationSeconds']),
        status: ChatStatus.parse(json['status']),
        latestVideoId: asStringOrNull(json['latestVideoId']),
        createdAt: asDateOrNull(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'language': language?.apiValue,
        'durationSeconds': durationSeconds,
        'status': status.apiValue,
        'latestVideoId': latestVideoId,
        'createdAt': dateToJson(createdAt),
      };

  ChatSummary copyWithProject(String? projectId) => ChatSummary(
        id: id,
        projectId: projectId,
        title: title,
        thumbnailUrl: thumbnailUrl,
        language: language,
        durationSeconds: durationSeconds,
        status: status,
        latestVideoId: latestVideoId,
        createdAt: createdAt,
      );
}

/// Full chat (one generation session).
class Chat {
  const Chat({
    required this.id,
    required this.title,
    required this.videoUrl,
    required this.status,
    this.projectId,
    this.userPrompt,
    this.language,
    this.durationSeconds,
    this.style,
    this.voiceType,
    this.analysis,
    this.script,
    this.videos = const [],
    this.activeJob,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? projectId;
  final String title;
  final String? userPrompt;
  final String videoUrl;
  final Language? language;
  final int? durationSeconds;
  final VideoStyle? style;
  final VoiceType? voiceType;
  final ChatStatus status;
  final VideoAnalysis? analysis;
  final Script? script;
  final List<GeneratedVideo> videos;
  final GenerationJob? activeJob;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title;
    final scriptTitle = script?.title ?? '';
    if (scriptTitle.trim().isNotEmpty) return scriptTitle;
    return analysis?.sourceTitle ?? 'Untitled idea';
  }

  /// Videos, newest first.
  List<GeneratedVideo> get videosNewestFirst {
    final list = [...videos];
    list.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  GeneratedVideo? get latestVideo {
    final sorted = videosNewestFirst;
    return sorted.isEmpty ? null : sorted.first;
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    final analysisJson = asJsonMapOrNull(json['analysis']);
    final scriptJson = asJsonMapOrNull(json['script']);
    final jobJson = asJsonMapOrNull(json['activeJob']);
    return Chat(
      id: asString(json['id']),
      projectId: asStringOrNull(json['projectId']),
      title: asString(json['title']),
      userPrompt: asStringOrNull(json['userPrompt']),
      videoUrl: asString(json['videoUrl']),
      language: Language.tryParse(json['language']),
      durationSeconds: asIntOrNull(json['durationSeconds']),
      style: VideoStyle.tryParse(json['style']),
      voiceType: VoiceType.tryParse(json['voiceType']),
      status: ChatStatus.parse(json['status']),
      analysis: analysisJson == null ? null : VideoAnalysis.fromJson(analysisJson),
      script: scriptJson == null ? null : Script.fromJson(scriptJson),
      videos: parseList(json['videos'], GeneratedVideo.fromJson),
      activeJob: jobJson == null ? null : GenerationJob.fromJson(jobJson),
      createdAt: asDateOrNull(json['createdAt']),
      updatedAt: asDateOrNull(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'title': title,
        'userPrompt': userPrompt,
        'videoUrl': videoUrl,
        'language': language?.apiValue,
        'durationSeconds': durationSeconds,
        'style': style?.apiValue,
        'voiceType': voiceType?.apiValue,
        'status': status.apiValue,
        'analysis': analysis?.toJson(),
        'script': script?.toJson(),
        'videos': videos.map((v) => v.toJson()).toList(),
        'activeJob': activeJob?.toJson(),
        'createdAt': dateToJson(createdAt),
        'updatedAt': dateToJson(updatedAt),
      };
}

/// Response of `GET /history`.
class HistoryPage {
  const HistoryPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<ChatSummary> items;
  final int page;
  final int pageSize;
  final int total;

  factory HistoryPage.fromJson(Map<String, dynamic> json) {
    final items = parseList(json['items'], ChatSummary.fromJson);
    return HistoryPage(
      items: items,
      page: asInt(json['page'], 1),
      pageSize: asInt(json['pageSize'], items.length),
      total: asInt(json['total'], items.length),
    );
  }
}
