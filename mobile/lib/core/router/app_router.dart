import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/analysis/presentation/analysis_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/generation/presentation/generation_screen.dart';
import '../../features/history/presentation/chat_entry_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/preview/presentation/preview_screen.dart';
import '../../features/projects/presentation/project_detail_screen.dart';
import '../../features/projects/presentation/projects_screen.dart';
import '../../features/script/presentation/script_config_screen.dart';
import '../../features/script/presentation/script_screen.dart';
import '../../features/settings/presentation/profile_screen.dart';
import '../bootstrap/bootstrap.dart';
import '../models/enums.dart';
import 'app_shell.dart';
import 'routes.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// Bridges Riverpod state (bootstrap + auth) to GoRouter's refresh/redirect.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _ref.listen<AsyncValue<void>>(bootstrapProvider, (_, __) => notifyListeners());
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;

  String? redirect(GoRouterState state) {
    final location = state.matchedLocation;
    final atSplash = location == AppRoutes.splash;
    final atLogin = location == AppRoutes.login;

    final boot = _ref.read(bootstrapProvider);
    if (!boot.hasValue) return atSplash ? null : AppRoutes.splash;

    final auth = _ref.read(authStateProvider);
    if (!auth.hasValue && !auth.hasError) {
      return atSplash ? null : AppRoutes.splash;
    }

    final signedIn = auth.valueOrNull != null;
    if (!signedIn) return atLogin ? null : AppRoutes.login;
    if (atSplash || atLogin) return AppRoutes.home;
    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: refresh,
    redirect: (context, state) => refresh.redirect(state),
    errorBuilder: (context, state) => const _NotFoundScreen(),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.history,
              builder: (context, state) => const HistoryScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.projects,
              builder: (context, state) => const ProjectsScreen(),
              routes: [
                GoRoute(
                  path: ':projectId',
                  builder: (context, state) => ProjectDetailScreen(
                    projectId: state.pathParameters['projectId']!,
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.profile,
              builder: (context, state) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
      // Chat flow (full-screen, above the shell). Specific paths first.
      GoRoute(
        path: '/chat/:chatId/analysis',
        builder: (context, state) =>
            AnalysisScreen(chatId: state.pathParameters['chatId']!),
      ),
      GoRoute(
        path: '/chat/:chatId/config',
        builder: (context, state) =>
            ScriptConfigScreen(chatId: state.pathParameters['chatId']!),
      ),
      GoRoute(
        path: '/chat/:chatId/script',
        builder: (context, state) =>
            ScriptScreen(chatId: state.pathParameters['chatId']!),
      ),
      GoRoute(
        path: '/chat/:chatId/generation',
        builder: (context, state) => GenerationScreen(
          chatId: state.pathParameters['chatId']!,
          jobId: state.uri.queryParameters['jobId'],
          resolution: Resolution.tryParse(state.uri.queryParameters['resolution']),
        ),
      ),
      GoRoute(
        path: '/chat/:chatId/preview',
        builder: (context, state) => PreviewScreen(
          chatId: state.pathParameters['chatId']!,
          videoId: state.uri.queryParameters['videoId'],
        ),
      ),
      GoRoute(
        path: '/chat/:chatId',
        builder: (context, state) =>
            ChatEntryScreen(chatId: state.pathParameters['chatId']!),
      ),
    ],
  );

  ref.onDispose(() {
    refresh.dispose();
    router.dispose();
  });
  return router;
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_rounded, size: 56),
            const SizedBox(height: 12),
            const Text('Page not found'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    );
  }
}
