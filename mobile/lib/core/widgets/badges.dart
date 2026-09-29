import 'package:flutter/material.dart';

import '../models/enums.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final ChatStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon) = switch (status) {
      ChatStatus.completed => (
          Colors.green.withAlpha(40),
          Colors.green.shade700,
          Icons.check_circle_rounded,
        ),
      ChatStatus.failed => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_rounded,
        ),
      ChatStatus.queued || ChatStatus.generating => (
          Colors.orange.withAlpha(45),
          Colors.orange.shade800,
          Icons.autorenew_rounded,
        ),
      ChatStatus.scriptReady => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.description_rounded,
        ),
      ChatStatus.analyzed => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.insights_rounded,
        ),
      ChatStatus.unknown => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.help_outline_rounded,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.label = 'Premium'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFF7043)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + brand color for a source platform.
class PlatformIcon extends StatelessWidget {
  const PlatformIcon({super.key, required this.platform, this.size = 22});

  final SourcePlatform platform;
  final double size;

  static IconData iconFor(SourcePlatform platform) => switch (platform) {
        SourcePlatform.youTube => Icons.smart_display_rounded,
        SourcePlatform.facebook => Icons.facebook_rounded,
        SourcePlatform.instagram => Icons.camera_alt_rounded,
        SourcePlatform.tikTok => Icons.music_note_rounded,
        SourcePlatform.other => Icons.link_rounded,
      };

  static Color colorFor(SourcePlatform platform, ColorScheme scheme) =>
      switch (platform) {
        SourcePlatform.youTube => const Color(0xFFFF0000),
        SourcePlatform.facebook => const Color(0xFF1877F2),
        SourcePlatform.instagram => const Color(0xFFE1306C),
        SourcePlatform.tikTok => scheme.onSurface,
        SourcePlatform.other => scheme.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    return Icon(
      iconFor(platform),
      size: size,
      color: colorFor(platform, Theme.of(context).colorScheme),
    );
  }
}
