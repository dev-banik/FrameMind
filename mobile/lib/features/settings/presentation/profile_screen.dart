import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/hive_cache.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/models/user_profile.dart';
import '../providers/settings_providers.dart';

/// `GET /health` status for the About section.
final _apiHealthProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(apiClientProvider).checkHealth(),
);

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'Your offline cache on this device will be cleared.',
      confirmLabel: 'Sign out',
    );
    if (!ok) return;
    await ref.read(hiveCacheProvider).clearAll();
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseUser = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider);
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    final name = profile.valueOrNull?.name.isNotEmpty == true
        ? profile.valueOrNull!.name
        : (firebaseUser?.displayName ?? 'FrameMind creator');
    final email = profile.valueOrNull?.email.isNotEmpty == true
        ? profile.valueOrNull!.email
        : (firebaseUser?.email ?? '');
    final photoUrl = profile.valueOrNull?.photoUrl ?? firebaseUser?.photoURL;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userProfileProvider);
          ref.invalidate(_apiHealthProvider);
          try {
            await ref.read(userProfileProvider.future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? CachedNetworkImageProvider(photoUrl)
                    : null,
                child: photoUrl == null || photoUrl.isEmpty
                    ? Text(
                        _initials(name),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (email.isNotEmpty)
              Text(
                email,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 24),
            profile.when(
              skipLoadingOnRefresh: true,
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => Card(
                child: ErrorView(
                  error: e,
                  compact: true,
                  onRetry: () => ref.invalidate(userProfileProvider),
                ),
              ),
              data: (user) => _PlanCard(user: user),
            ),
            const SizedBox(height: 24),
            Text('Appearance', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_rounded),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded),
                  label: Text('Dark'),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).setMode(selection.first),
            ),
            const SizedBox(height: 24),
            Text('About', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('Originality promise'),
                    subtitle: Text(
                      'FrameMind only learns the category, theme, mood, style and pace of '
                      'a video. Every script and video is newly generated.',
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Server'),
                    subtitle: Text(AppConfig.apiBaseUrl),
                    trailing: Consumer(
                      builder: (context, ref, _) {
                        final health = ref.watch(_apiHealthProvider);
                        return health.when(
                          loading: () => const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (_, __) => const Icon(Icons.cloud_off_rounded),
                          data: (ok) => Icon(
                            ok ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
                            color: ok ? Colors.green : theme.colorScheme.error,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withAlpha(120)),
              ),
              onPressed: () => _signOut(context, ref),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final limit = user.dailyVideoLimit;
    final usage = limit == null || limit == 0
        ? null
        : (user.videosGeneratedToday / limit).clamp(0.0, 1.0).toDouble();

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withAlpha(140),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${user.plan.label} plan',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                if (user.isPremium) const PremiumBadge(label: 'Active'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    limit == null
                        ? 'Unlimited videos per day'
                        : '${user.videosGeneratedToday} of $limit videos used today',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (user.quotaExhausted)
                  Text(
                    'Limit reached',
                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.error),
                  ),
              ],
            ),
            if (usage != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usage,
                  minHeight: 8,
                  color: user.quotaExhausted ? scheme.error : scheme.primary,
                  backgroundColor: scheme.surface.withAlpha(160),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.high_quality_rounded, size: 20, color: scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text('Max resolution: ${user.maxResolution.label}'),
              ],
            ),
            if (!user.isPremium) ...[
              const SizedBox(height: 12),
              Text(
                'Upgrade to Premium for 1080p videos and more daily generations.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
