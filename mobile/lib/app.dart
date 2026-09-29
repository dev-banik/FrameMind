import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/snackbar.dart';
import 'features/auth/providers/auth_providers.dart';
import 'features/settings/providers/settings_providers.dart';

class FrameMindApp extends ConsumerWidget {
  const FrameMindApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Register / unregister for push notifications as the account changes.
    ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (after != null && after.uid != before?.uid) {
        ref.read(pushServiceProvider).onSignedIn(after);
      } else if (after == null && before != null) {
        ref.read(pushServiceProvider).onSignedOut();
      }
    });

    return MaterialApp.router(
      title: 'FrameMind',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
