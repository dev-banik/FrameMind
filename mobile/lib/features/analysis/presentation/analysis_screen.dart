import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/network_thumbnail.dart';
import '../../../core/widgets/state_views.dart';
import '../../history/providers/history_providers.dart';
import '../data/models/video_analysis.dart';

class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider(chatId));

    return Scaffold(
      appBar: AppBar(title: const Text('Video analysis')),
      body: AsyncValueView(
        value: chat,
        loadingMessage: 'Loading analysis…',
        onRetry: () => ref.invalidate(chatControllerProvider(chatId)),
        data: (chat) {
          final analysis = chat.analysis;
          if (analysis == null) {
            return EmptyView(
              icon: Icons.insights_outlined,
              title: 'No analysis available',
              message: 'This chat has no analysis. Try analyzing the video again.',
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Back to Home'),
              ),
            );
          }
          return _AnalysisBody(analysis: analysis, videoUrl: chat.videoUrl);
        },
      ),
      bottomNavigationBar: chat.hasValue
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.config(chatId)),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Continue'),
              ),
            )
          : null,
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  const _AnalysisBody({required this.analysis, required this.videoUrl});

  final VideoAnalysis analysis;
  final String videoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetworkThumbnail(url: analysis.thumbnailUrl, borderRadius: 18),
              if (analysis.sourceDurationSeconds != null)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(170),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      formatClock(Duration(seconds: analysis.sourceDurationSeconds!)),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            PlatformIcon(platform: analysis.sourcePlatform, size: 20),
            const SizedBox(width: 6),
            Text(
              analysis.sourcePlatform.label,
              style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          analysis.sourceTitle.isEmpty ? videoUrl : analysis.sourceTitle,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        InfoBanner(
          icon: Icons.verified_user_outlined,
          message: 'We only use the style - your script will be 100% original.',
        ),
        const SizedBox(height: 20),
        _AttributeGrid(analysis: analysis),
        if (analysis.characters.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('Character types'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in analysis.characters)
                Chip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 18),
                  label: Text(c),
                ),
            ],
          ),
        ],
        if (analysis.storyPattern.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('Story pattern'),
          const SizedBox(height: 6),
          Text(analysis.storyPattern, style: theme.textTheme.bodyLarge),
        ],
        if (analysis.summary.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('Format'),
          const SizedBox(height: 6),
          Text(
            analysis.summary,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _AttributeGrid extends StatelessWidget {
  const _AttributeGrid({required this.analysis});

  final VideoAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.category_outlined, 'Category', analysis.category),
      (Icons.lightbulb_outline_rounded, 'Theme', analysis.theme),
      (Icons.mood_rounded, 'Mood', analysis.mood),
      (Icons.palette_outlined, 'Style', analysis.style),
      (Icons.speed_rounded, 'Pace', analysis.pace),
    ].where((item) => item.$3.trim().isNotEmpty).toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (icon, label, value) in items)
          _AttributeChip(icon: icon, label: label, value: value),
      ],
    );
  }
}

class _AttributeChip extends StatelessWidget {
  const _AttributeChip({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withAlpha(150),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer.withAlpha(180),
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
