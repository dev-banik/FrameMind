import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/widgets/badges.dart';
import '../../../settings/data/models/user_profile.dart';
import '../../../settings/providers/settings_providers.dart';

/// Lets the user choose 720p / 1080p. 1080p is disabled for Free users.
Future<Resolution?> showResolutionSheet(BuildContext context) {
  return showModalBottomSheet<Resolution>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _ResolutionSheet(),
  );
}

class _ResolutionSheet extends ConsumerStatefulWidget {
  const _ResolutionSheet();

  @override
  ConsumerState<_ResolutionSheet> createState() => _ResolutionSheetState();
}

class _ResolutionSheetState extends ConsumerState<_ResolutionSheet> {
  Resolution? _selected;

  bool _allowed(Resolution r, UserProfile? user) {
    if (r == Resolution.p720) return true;
    return user?.canUse(r) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(userProfileProvider);
    final user = profile.valueOrNull;

    final last = Resolution.tryParse(ref.read(appPreferencesProvider).lastResolution);
    final selected = _selected ??
        (last != null && _allowed(last, user) ? last : Resolution.p720);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Generate video', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Your script is saved automatically before generation starts.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (profile.isLoading && user == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            for (final r in Resolution.values)
              _ResolutionTile(
                resolution: r,
                selected: selected == r,
                enabled: _allowed(r, user),
                onTap: () => setState(() => _selected = r),
              ),
            if (user != null && user.quotaExhausted) ...[
              const SizedBox(height: 8),
              Text(
                "You've reached today's limit of ${user.dailyVideoLimit} videos.",
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ] else if (user != null && !user.isUnlimited) ...[
              const SizedBox(height: 8),
              Text(
                '${user.remainingToday} of ${user.dailyVideoLimit} videos left today.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: user != null && user.quotaExhausted
                  ? null
                  : () => Navigator.of(context).pop(selected),
              icon: const Icon(Icons.movie_creation_rounded),
              label: Text('Generate ${selected.label} video'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolutionTile extends StatelessWidget {
  const _ResolutionTile({
    required this.resolution,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Resolution resolution;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final description = resolution == Resolution.p1080
        ? 'Full HD - sharpest quality'
        : 'HD - fast and great on phones';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resolution.label,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        Text(description, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (!enabled) const PremiumBadge(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
