import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Compile-time and platform configuration.
///
/// Override the API with `--dart-define=API_BASE_URL=https://api.example.com/api`.
abstract final class AppConfig {
  static const String appName = 'FrameMind';
  static const String galleryAlbum = 'FrameMind';

  static const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Base URL of the REST API, without a trailing slash.
  static String get apiBaseUrl {
    var url = _apiBaseUrlOverride;
    if (url.isEmpty) {
      // 10.0.2.2 is the host machine as seen from the Android emulator.
      url = (!kIsWeb && Platform.isAndroid)
          ? 'http://10.0.2.2:8080/api'
          : 'http://localhost:8080/api';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 45);

  /// Video analysis may take up to ~60s server-side.
  static const Duration analyzeTimeout = Duration(seconds: 120);

  /// Script generation calls an LLM and can be slow.
  static const Duration scriptTimeout = Duration(seconds: 120);

  static const Duration jobPollInterval = Duration(seconds: 4);

  static const int historyPageSize = 20;

  static const int minDurationSeconds = 15;
  static const int maxDurationSeconds = 300;
}
