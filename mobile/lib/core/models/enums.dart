/// API enums. The backend serializes enums as their PascalCase names; parsing
/// is case-insensitive and tolerant of unknown values so that a newer backend
/// never crashes an older app.
library;

abstract interface class ApiEnum {
  String get apiValue;
}

T? parseApiEnum<T extends ApiEnum>(List<T> values, Object? raw) {
  if (raw == null) return null;
  final normalized = raw.toString().trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final value in values) {
    if (value.apiValue.toLowerCase() == normalized) return value;
  }
  return null;
}

enum Language implements ApiEnum {
  english('English', 'English'),
  bangla('Bangla', 'Bangla (বাংলা)'),
  hindi('Hindi', 'Hindi (हिन्दी)');

  const Language(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static Language? tryParse(Object? raw) => parseApiEnum(values, raw);
}

enum VideoStyle implements ApiEnum {
  animation('Animation', 'Animation'),
  realistic('Realistic', 'Realistic'),
  cartoon('Cartoon', 'Cartoon'),
  cinematic('Cinematic', 'Cinematic'),
  anime('Anime', 'Anime');

  const VideoStyle(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static VideoStyle? tryParse(Object? raw) => parseApiEnum(values, raw);
}

enum VoiceType implements ApiEnum {
  male('Male', 'Male'),
  female('Female', 'Female'),
  child('Child', 'Child'),
  narrator('Narrator', 'Narrator');

  const VoiceType(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static VoiceType? tryParse(Object? raw) => parseApiEnum(values, raw);
}

enum Resolution implements ApiEnum {
  p720('P720', '720p'),
  p1080('P1080', '1080p');

  const Resolution(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static Resolution? tryParse(Object? raw) => parseApiEnum(values, raw);

  static Resolution parse(Object? raw) => tryParse(raw) ?? Resolution.p720;
}

enum ChatStatus implements ApiEnum {
  analyzed('Analyzed', 'Analyzed'),
  scriptReady('ScriptReady', 'Script ready'),
  queued('Queued', 'Queued'),
  generating('Generating', 'Generating'),
  completed('Completed', 'Completed'),
  failed('Failed', 'Failed'),
  unknown('Unknown', 'Unknown');

  const ChatStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  /// Values that can be used as a server-side filter.
  static List<ChatStatus> get filterable =>
      values.where((s) => s != ChatStatus.unknown).toList();

  static ChatStatus parse(Object? raw) =>
      parseApiEnum(values, raw) ?? ChatStatus.unknown;

  bool get isInProgress =>
      this == ChatStatus.queued || this == ChatStatus.generating;
}

enum GenerationStage implements ApiEnum {
  queued('Queued', 'Queued'),
  analyzing('Analyzing', 'Analyzing'),
  generatingScript('GeneratingScript', 'Generating Script'),
  generatingVoice('GeneratingVoice', 'Generating Voice'),
  generatingVideo('GeneratingVideo', 'Generating Video'),
  rendering('Rendering', 'Rendering'),
  complete('Complete', 'Complete'),
  failed('Failed', 'Failed'),
  unknown('Unknown', 'Working');

  const GenerationStage(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static GenerationStage parse(Object? raw) =>
      parseApiEnum(values, raw) ?? GenerationStage.unknown;

  bool get isTerminal =>
      this == GenerationStage.complete || this == GenerationStage.failed;
}

enum Plan implements ApiEnum {
  free('Free', 'Free'),
  premium('Premium', 'Premium');

  const Plan(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static Plan parse(Object? raw) => parseApiEnum(values, raw) ?? Plan.free;
}

enum SourcePlatform implements ApiEnum {
  youTube('YouTube', 'YouTube'),
  facebook('Facebook', 'Facebook'),
  instagram('Instagram', 'Instagram'),
  tikTok('TikTok', 'TikTok'),
  other('Other', 'Other');

  const SourcePlatform(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static SourcePlatform parse(Object? raw) =>
      parseApiEnum(values, raw) ?? SourcePlatform.other;
}
