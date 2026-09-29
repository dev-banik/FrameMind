import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/providers/settings_providers.dart';

/// Shows today's usage (e.g. "2/5 today") or "Unlimited" for Premium.
class QuotaChip extends ConsumerWidget {
  const QuotaChip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final scheme = Theme.of(context).colorScheme;

    return profile.when(
      loading: () => const SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => ActionChip(
        avatar: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Quota'),
        onPressed: () => ref.invalidate(userProfileProvider),
      ),
      data: (user) {
        final exhausted = user.quotaExhausted;
        final label = user.isUnlimited
            ? 'Unlimited'
            : '${user.videosGeneratedToday}/${user.dailyVideoLimit} today';
        return ActionChip(
          onPressed: onTap,
          avatar: Icon(
            user.isPremium ? Icons.workspace_premium_rounded : Icons.bolt_rounded,
            size: 18,
            color: exhausted ? scheme.error : scheme.primary,
          ),
          label: Text(label),
          side: BorderSide(
            color: exhausted ? scheme.error : scheme.outlineVariant,
          ),
          tooltip: exhausted
              ? 'Daily limit reached'
              : user.isUnlimited
                  ? 'Premium plan'
                  : '${user.remainingToday} videos left today',
        );
      },
    );
  }
}
