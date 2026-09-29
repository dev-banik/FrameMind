import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analysis_repository.dart';
import '../data/models/video_analysis.dart';

/// Runs `POST /video/analyze` for the Home screen. State is `null` until the
/// first analysis succeeds.
class AnalyzeController extends AutoDisposeAsyncNotifier<AnalyzeResult?> {
  @override
  AnalyzeResult? build() => null;

  Future<AnalyzeResult?> analyze({
    required String videoUrl,
    String? projectId,
    String? userPrompt,
  }) async {
    if (state.isLoading) return null;
    state = const AsyncLoading<AnalyzeResult?>();
    final result = await AsyncValue.guard(
      () => ref.read(analysisRepositoryProvider).analyze(
            videoUrl: videoUrl,
            projectId: projectId,
            userPrompt: userPrompt,
          ),
    );
    state = result;
    return result.valueOrNull;
  }

  void reset() => state = const AsyncData<AnalyzeResult?>(null);
}

final analyzeControllerProvider =
    AsyncNotifierProvider.autoDispose<AnalyzeController, AnalyzeResult?>(
  AnalyzeController.new,
);
