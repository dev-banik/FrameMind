import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/state_views.dart';
import '../../history/providers/chat_list_refresh.dart';
import '../../history/providers/history_providers.dart';
import '../data/generation_repository.dart';
import '../data/models/generation_models.dart';
import '../providers/generation_providers.dart';
import 'widgets/stage_stepper.dart';

/// Shows live progress of a generation job (polled every 4 s).
class GenerationScreen extends ConsumerStatefulWidget {
  const GenerationScreen({
    super.key,
    required this.chatId,
    this.jobId,
    this.resolution,
  });

  final String chatId;
  final String? jobId;
  final Resolution? resolution;

  @override
  ConsumerState<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends ConsumerState<GenerationScreen> {
  String? _jobId;
  bool _navigated = false;
  bool _retrying = false;

  /// Last non-terminal stage seen, used to show where a failure happened.
  GenerationStage? _lastStage;

  @override
  void initState() {
    super.initState();
    _jobId = widget.jobId;
  }

  void _onJobUpdate(GenerationJob job) {
    if (!job.isTerminal && job.stage != GenerationStage.unknown) {
      _lastStage = job.stage;
    }
    if (_navigated || !job.isTerminal) return;
    ref.invalidate(chatControllerProvider(widget.chatId));
    refreshChatListsAndQuota(ref.invalidate);
    if (job.isComplete) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement(AppRoutes.preview(widget.chatId, videoId: job.videoId));
      });
    }
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      final job = await ref.read(generationRepositoryProvider).generate(
            chatId: widget.chatId,
            resolution: widget.resolution ?? Resolution.p720,
          );
      refreshChatListsAndQuota(ref.invalidate);
      if (!mounted) return;
      setState(() {
        _jobId = job.id;
        _lastStage = null;
        _retrying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _retrying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobId = _jobId;

    // No job id in the route: resolve from the chat's active job.
    if (jobId == null) {
      final chat = ref.watch(chatControllerProvider(widget.chatId));
      return Scaffold(
        appBar: AppBar(title: const Text('Generating video')),
        body: AsyncValueView(
          value: chat,
          onRetry: () => ref.invalidate(chatControllerProvider(widget.chatId)),
          data: (chat) {
            final active = chat.activeJob;
            if (active != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _jobId == null) setState(() => _jobId = active.id);
              });
              return const LoadingView();
            }
            if (chat.latestVideo != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.pushReplacement(AppRoutes.preview(chat.id));
              });
              return const LoadingView();
            }
            return EmptyView(
              icon: Icons.movie_filter_outlined,
              title: 'No generation in progress',
              message: 'Open your script to generate a video.',
              action: FilledButton(
                onPressed: () => context.pushReplacement(AppRoutes.script(chat.id)),
                child: const Text('Open script'),
              ),
            );
          },
        ),
      );
    }

    ref.listen<AsyncValue<GenerationJob>>(jobPollingProvider(jobId), (previous, next) {
      final job = next.valueOrNull;
      if (job != null) _onJobUpdate(job);
    });
    final jobAsync = ref.watch(jobPollingProvider(jobId));
    final job = jobAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generating video'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: _leave,
        ),
      ),
      body: SafeArea(
        child: jobAsync.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const LoadingView(message: 'Connecting to the render queue…'),
          error: (e, _) => job == null
              ? ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(jobPollingProvider(jobId)),
                )
              : _ProgressBody(
                  job: job,
                  connectionError: e,
                  onReconnect: () => ref.invalidate(jobPollingProvider(jobId)),
                  onRetry: _retry,
                  retrying: _retrying,
                  onLeave: _leave,
                  chatId: widget.chatId,
                  lastKnownStage: _lastStage,
                ),
          data: (job) => _ProgressBody(
            job: job,
            onRetry: _retry,
            retrying: _retrying,
            onLeave: _leave,
            chatId: widget.chatId,
            lastKnownStage: _lastStage,
          ),
        ),
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({
    required this.job,
    required this.onRetry,
    required this.retrying,
    required this.onLeave,
    required this.chatId,
    this.connectionError,
    this.onReconnect,
    this.lastKnownStage,
  });

  final GenerationJob job;
  final VoidCallback onRetry;
  final bool retrying;
  final VoidCallback onLeave;
  final String chatId;
  final Object? connectionError;
  final VoidCallback? onReconnect;
  final GenerationStage? lastKnownStage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = job.isFailed;
    final percent = job.isComplete ? 100 : job.progress.clamp(0, 100);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (connectionError != null) ...[
          InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: 'Connection lost - showing last known progress.',
            action: TextButton(onPressed: onReconnect, child: const Text('Retry')),
          ),
          const SizedBox(height: 16),
        ],
        Center(
          child: SizedBox(
            width: 148,
            height: 148,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: failed ? 1 : (percent == 0 ? null : percent / 100),
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  color: failed ? scheme.error : scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
                Center(
                  child: failed
                      ? Icon(Icons.error_outline_rounded, size: 56, color: scheme.error)
                      : Text(
                          '$percent%',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          failed
              ? 'Generation failed'
              : job.isComplete
                  ? 'Your video is ready!'
                  : job.stage == GenerationStage.queued
                      ? 'Waiting in the queue…'
                      : '${job.stage.label}…',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: failed ? 1 : percent / 100,
            minHeight: 8,
            color: failed ? scheme.error : null,
          ),
        ),
        const SizedBox(height: 24),
        StageStepper(job: job, lastKnownStage: lastKnownStage),
        const SizedBox(height: 24),
        if (failed) ...[
          InfoBanner(
            isError: true,
            icon: Icons.error_outline_rounded,
            message: job.error?.isNotEmpty == true
                ? job.error!
                : 'Something went wrong while rendering your video.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: retrying ? null : onRetry,
            icon: retrying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.pushReplacement(AppRoutes.script(chatId)),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Edit script'),
          ),
        ] else if (!job.isComplete) ...[
          const InfoBanner(
            icon: Icons.notifications_active_outlined,
            message: "This can take a few minutes. Feel free to leave - we'll send you a "
                'notification when your video is ready.',
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onLeave,
            child: const Text("I'll wait for the notification"),
          ),
        ] else
          FilledButton.icon(
            onPressed: () => context.pushReplacement(
              AppRoutes.preview(chatId, videoId: job.videoId),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Watch video'),
          ),
      ],
    );
  }
}
