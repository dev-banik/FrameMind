import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` with the loaded [SharedPreferences] instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final appPreferencesProvider = Provider<AppPreferences>(
  (ref) => AppPreferences(ref.watch(sharedPreferencesProvider)),
);

/// Non-sensitive UI preferences. Anything sensitive goes to [SecureStore].
class AppPreferences {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _themeModeKey = 'theme_mode';
  static const _languageKey = 'last_language';
  static const _durationKey = 'last_duration_seconds';
  static const _styleKey = 'last_style';
  static const _voiceKey = 'last_voice';
  static const _resolutionKey = 'last_resolution';

  ThemeMode get themeMode {
    switch (_prefs.getString(_themeModeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeModeKey, mode.name);

  String? get lastLanguage => _prefs.getString(_languageKey);
  int? get lastDurationSeconds => _prefs.getInt(_durationKey);
  String? get lastStyle => _prefs.getString(_styleKey);
  String? get lastVoice => _prefs.getString(_voiceKey);
  String? get lastResolution => _prefs.getString(_resolutionKey);

  Future<void> setLastScriptConfig({
    required String language,
    required int durationSeconds,
    required String style,
    required String voice,
  }) async {
    await Future.wait([
      _prefs.setString(_languageKey, language),
      _prefs.setInt(_durationKey, durationSeconds),
      _prefs.setString(_styleKey, style),
      _prefs.setString(_voiceKey, voice),
    ]);
  }

  Future<void> setLastResolution(String resolution) =>
      _prefs.setString(_resolutionKey, resolution);
}
