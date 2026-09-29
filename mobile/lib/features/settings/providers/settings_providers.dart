import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_preferences.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/models/user_profile.dart';
import '../data/user_repository.dart';

/// Profile + plan + quota from `GET /users/me`. Invalidate after generating
/// a video to refresh the quota.
final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    throw StateError('Not signed in');
  }
  return ref.watch(userRepositoryProvider).getMe();
});

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(appPreferencesProvider).themeMode;

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(appPreferencesProvider).setThemeMode(mode);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
