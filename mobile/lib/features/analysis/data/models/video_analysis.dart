import '../../../../core/models/enums.dart';
import '../../../../core/utils/json.dart';

/// Abstract, non-identifying attributes extracted from the source video.
class VideoAnalysis {
  const VideoAnalysis({
    required this.sourceTitle,
    required this.sourcePlatform,
    this.thumbnailUrl,
    this.sourceDurationSeconds,
    this.category = '',
    this.theme = '',
    this.mood = '',
    this.style = '',
    this.characters = const [],
    this.pace = '',
    this.storyPattern = '',
    this.summary = '',
  });

  final String sourceTitle;
  final SourcePlatform sourcePlatform;
  final String? thumbnailUrl;
  final int? sourceDurationSeconds;
  final String category;
  final String theme;
  final String mood;
  final String style;
  final List<String> characters;
  final String pace;
  final String storyPattern;
  final String summary;

  factory VideoAnalysis.fromJson(Map<String, dynamic> json) => VideoAnalysis(
        sourceTitle: asString(json['sourceTitle']),
        sourcePlatform: SourcePlatform.parse(json['sourcePlatform']),
        thumbnailUrl: asStringOrNull(json['thumbnailUrl']),
        sourceDurationSeconds: asIntOrNull(json['sourceDurationSeconds']),
        category: asString(json['category']),
        theme: asString(json['theme']),
        mood: asString(json['mood']),
        style: asString(json['style']),
        characters: asStringList(json['characters']),
        pace: asString(json['pace']),
        storyPattern: asString(json['storyPattern']),
        summary: asString(json['summary']),
      );

  Map<String, dynamic> toJson() => {
        'sourceTitle': sourceTitle,
        'sourcePlatform': sourcePlatform.apiValue,
        'thumbnailUrl': thumbnailUrl,
        'sourceDurationSeconds': sourceDurationSeconds,
        'category': category,
        'theme': theme,
        'mood': mood,
        'style': style,
        'characters': characters,
        'pace': pace,
        'storyPattern': storyPattern,
        'summary': summary,
      };
}

/// Response of `POST /video/analyze`.
class AnalyzeResult {
  const AnalyzeResult({required this.chatId, required this.analysis});

  final String chatId;
  final VideoAnalysis analysis;

  factory AnalyzeResult.fromJson(Map<String, dynamic> json) => AnalyzeResult(
        chatId: asString(json['chatId']),
        analysis: VideoAnalysis.fromJson(asJsonMap(json['analysis'])),
      );
}
