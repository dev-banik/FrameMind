import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../data/generation_repository.dart';
import '../data/models/generation_models.dart';

/// Polls `GET /video/jobs/{jobId}` every [AppConfig.jobPollInterval] until the
/// job completes or fails. Polling (including the in-flight request) stops as
/// soon as nobody listens any more (autoDispose).
final jobPollingProvider =
    StreamProvider.autoDispose.family<GenerationJob, String>((ref, jobId) {
  final repo = ref.watch(generationRepositoryProvider);
  final controller = StreamController<GenerationJob>();
  final cancelToken = CancelToken();
  Timer? timer;
  var disposed = false;
  var consecutiveFailures = 0;

  Future<void> poll() async {
    if (disposed) return;
    try {
      final job = await repo.getJob(jobId, cancelToken: cancelToken);
      if (disposed) return;
      consecutiveFailures = 0;
      controller.add(job);
      if (job.isTerminal) return; // stop polling
    } on ApiException catch (e) {
      if (disposed || e.isCancelled) return;
      consecutiveFailures++;
      // Tolerate transient network blips; surface persistent failures.
      if (!e.isOffline || consecutiveFailures >= 4) {
        controller.addError(e);
        if (!e.isOffline) return;
      }
    } catch (e) {
      if (disposed) return;
      controller.addError(e);
      return;
    }
    if (!disposed) {
      timer = Timer(AppConfig.jobPollInterval, poll);
    }
  }

  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    cancelToken.cancel('Job polling disposed');
    controller.close();
  });

  poll();
  return controller.stream;
});
