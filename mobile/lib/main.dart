import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/app_preferences.dart';

/// Entry point.
///
/// Firebase and Hive are initialised by the splash screen (see
/// `core/bootstrap/bootstrap.dart`) using the native Firebase config files
/// (`google-services.json` / `GoogleService-Info.plist`), so no generated
/// `firebase_options.dart` is required.
///
/// Run with: `flutter run --dart-define=API_BASE_URL=http://<host>:8080/api`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const FrameMindApp(),
    ),
  );
}
