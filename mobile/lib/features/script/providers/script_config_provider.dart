import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/enums.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/utils/formatters.dart';

/// Preset durations shown in the dropdown (null entry = Custom).
const List<int> kPresetDurations = [30, 60, 90, 120];

class ScriptConfig {
  const ScriptConfig({
    required this.language,
    required this.durationSeconds,
    required this.style,
    required this.voice,
  });

  final Language language;
  final int durationSeconds;
  final VideoStyle style;
  final VoiceType voice;

  bool get isCustomDuration => !kPresetDurations.contains(durationSeconds);

  ScriptConfig copyWith({
    Language? language,
    int? durationSeconds,
    VideoStyle? style,
    VoiceType? voice,
  }) =>
      ScriptConfig(
        language: language ?? this.language,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        style: style ?? this.style,
        voice: voice ?? this.voice,
      );
}

/// The last script configuration the user picked (persisted in prefs).
class LastScriptConfigController extends Notifier<ScriptConfig> {
  @override
  ScriptConfig build() {
    final prefs = ref.watch(appPreferencesProvider);
    final duration = prefs.lastDurationSeconds ?? 60;
    return ScriptConfig(
      language: Language.tryParse(prefs.lastLanguage) ?? Language.english,
      durationSeconds: clampInt(
        duration,
        AppConfig.minDurationSeconds,
        AppConfig.maxDurationSeconds,
      ),
      style: VideoStyle.tryParse(prefs.lastStyle) ?? VideoStyle.animation,
      voice: VoiceType.tryParse(prefs.lastVoice) ?? VoiceType.narrator,
    );
  }

  Future<void> remember(ScriptConfig config) async {
    state = config;
    await ref.read(appPreferencesProvider).setLastScriptConfig(
          language: config.language.apiValue,
          durationSeconds: config.durationSeconds,
          style: config.style.apiValue,
          voice: config.voice.apiValue,
        );
  }
}

final lastScriptConfigProvider =
    NotifierProvider<LastScriptConfigController, ScriptConfig>(
  LastScriptConfigController.new,
);
