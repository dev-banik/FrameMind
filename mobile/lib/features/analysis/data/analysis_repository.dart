import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'models/video_analysis.dart';

class AnalysisRepository {
  AnalysisRepository(this._api);

  final ApiClient _api;

  /// `POST /video/analyze` - creates a chat in status `Analyzed`.
  Future<AnalyzeResult> analyze({
    required String videoUrl,
    String? projectId,
    String? userPrompt,
  }) async {
    final prompt = userPrompt?.trim();
    final data = await _api.post(
      '/video/analyze',
      data: {
        'videoUrl': videoUrl,
        'projectId': projectId,
        'userPrompt': (prompt == null || prompt.isEmpty) ? null : prompt,
      },
      receiveTimeout: AppConfig.analyzeTimeout,
    );
    return AnalyzeResult.fromJson(asJsonMap(data));
  }
}

final analysisRepositoryProvider = Provider<AnalysisRepository>(
  (ref) => AnalysisRepository(ref.watch(apiClientProvider)),
);
