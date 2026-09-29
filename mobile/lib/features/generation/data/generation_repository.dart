import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'models/generation_models.dart';

/// `/video/*` generation endpoints.
class GenerationRepository {
  GenerationRepository(this._api);

  final ApiClient _api;

  /// `POST /video/generate` -> 202 GenerationJob
  Future<GenerationJob> generate({
    required String chatId,
    required Resolution resolution,
  }) async {
    final data = await _api.post(
      '/video/generate',
      data: {'chatId': chatId, 'resolution': resolution.apiValue},
    );
    return GenerationJob.fromJson(asJsonMap(data));
  }

  /// `GET /video/jobs/{jobId}`
  Future<GenerationJob> getJob(String jobId, {CancelToken? cancelToken}) async {
    final data = await _api.get('/video/jobs/$jobId', cancelToken: cancelToken);
    return GenerationJob.fromJson(asJsonMap(data));
  }

  /// `GET /video/{videoId}/download` -> signed URL
  Future<DownloadInfo> getDownloadInfo(String videoId) async {
    final data = await _api.get('/video/$videoId/download');
    return DownloadInfo.fromJson(asJsonMap(data));
  }
}

final generationRepositoryProvider = Provider<GenerationRepository>(
  (ref) => GenerationRepository(ref.watch(apiClientProvider)),
);
