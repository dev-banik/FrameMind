import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../data/models/generation_models.dart';

/// Visible pipeline steps, in order.
const List<GenerationStage> kDisplayStages = [
  GenerationStage.analyzing,
  GenerationStage.generatingScript,
  GenerationStage.generatingVoice,
  GenerationStage.generatingVideo,
  GenerationStage.rendering,
  GenerationStage.complete,
];

enum StepStatus { done, active, pending, failed }

/// Maps a job to the status of each displayed step. Analysis and script
/// always happen before a video job exists, so earlier stages show as done.
List<StepStatus> stepStatuses(GenerationJob job, {GenerationStage? lastKnownStage}) {
  final stage = job.stage;
  int activeIndex;
  switch (stage) {
    case GenerationStage.complete:
      return List.filled(kDisplayStages.length, StepStatus.done);
    case GenerationStage.queued:
    case GenerationStage.unknown:
      // Waiting to start voice generation.
      activeIndex = kDisplayStages.indexOf(GenerationStage.generatingVoice);
    case GenerationStage.failed:
      final last = lastKnownStage;
      final idx = last == null ? -1 : kDisplayStages.indexOf(last);
      // Unknown failure point: mark the first video stage as failed.
      activeIndex = idx >= 0 ? idx : _failureIndexFromProgress(job.progress);
    default:
      activeIndex = kDisplayStages.indexOf(stage);
  }
  if (activeIndex < 0) activeIndex = 0;

  return [
    for (var i = 0; i < kDisplayStages.length; i++)
      if (i < activeIndex)
        StepStatus.done
      else if (i == activeIndex)
        (stage == GenerationStage.failed ? StepStatus.failed : StepStatus.active)
      else
        StepStatus.pending,
  ];
}

int _failureIndexFromProgress(int progress) {
  // Rough mapping of overall progress to the video pipeline steps.
  if (progress < 30) return 2; // voice
  if (progress < 85) return 3; // video
  return 4; // rendering
}

class StageStepper extends StatelessWidget {
  const StageStepper({super.key, required this.job, this.lastKnownStage});

  final GenerationJob job;
  final GenerationStage? lastKnownStage;

  @override
  Widget build(BuildContext context) {
    final statuses = stepStatuses(job, lastKnownStage: lastKnownStage);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        for (var i = 0; i < kDisplayStages.length; i++)
          _StepRow(
            label: kDisplayStages[i].label,
            status: statuses[i],
            isLast: i == kDisplayStages.length - 1,
            scheme: scheme,
            textTheme: theme.textTheme,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.status,
    required this.isLast,
    required this.scheme,
    required this.textTheme,
  });

  final String label;
  final StepStatus status;
  final bool isLast;
  final ColorScheme scheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      StepStatus.done => scheme.primary,
      StepStatus.active => scheme.primary,
      StepStatus.failed => scheme.error,
      StepStatus.pending => scheme.outlineVariant,
    };
    final Widget indicator = switch (status) {
      StepStatus.done => Icon(Icons.check_circle_rounded, color: color, size: 26),
      StepStatus.failed => Icon(Icons.cancel_rounded, color: color, size: 26),
      StepStatus.active => SizedBox(
          width: 26,
          height: 26,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CircularProgressIndicator(strokeWidth: 2.6, color: color),
          ),
        ),
      StepStatus.pending => Icon(Icons.radio_button_unchecked_rounded, color: color, size: 26),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                indicator,
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: status == StepStatus.done
                          ? scheme.primary
                          : scheme.outlineVariant.withAlpha(140),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: isLast ? 0 : 18),
              child: Text(
                label,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight:
                      status == StepStatus.active ? FontWeight.w700 : FontWeight.w500,
                  color: status == StepStatus.pending
                      ? scheme.onSurfaceVariant
                      : status == StepStatus.failed
                          ? scheme.error
                          : scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
