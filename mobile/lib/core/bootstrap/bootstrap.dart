import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';
import '../storage/hive_cache.dart';

class BootstrapException extends AppException {
  const BootstrapException(super.message);
}

/// One-time app initialisation, driven by the splash screen:
/// Firebase (from native config files) + Hive offline cache.
///
/// Firebase is initialised WITHOUT explicit options, so it reads
/// `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
/// (both produced by `flutterfire configure`).
final bootstrapProvider = FutureProvider<void>((ref) async {
  final started = DateTime.now();

  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase.initializeApp failed: $e');
      throw const BootstrapException(
        'Firebase is not configured for this build. Run `flutterfire configure` '
        'so google-services.json / GoogleService-Info.plist are present, then rebuild.',
      );
    }
  }

  try {
    await HiveCache.init();
  } catch (e) {
    // The app still works online without the offline cache.
    debugPrint('Hive init failed: $e');
  }

  // Keep the splash animation visible briefly to avoid a jarring flash.
  const minSplash = Duration(milliseconds: 900);
  final elapsed = DateTime.now().difference(started);
  if (elapsed < minSplash) {
    await Future<void>.delayed(minSplash - elapsed);
  }
});

/// True once [bootstrapProvider] completed successfully.
final isBootstrappedProvider = Provider<bool>(
  (ref) => ref.watch(bootstrapProvider).hasValue,
);
