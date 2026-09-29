import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Thin wrapper around [Dio] that maps every failure to [ApiException].
/// Feature repositories build typed endpoints on top of it.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) {
    return _send(() => _dio.get<dynamic>(
          path,
          queryParameters: _clean(query),
          cancelToken: cancelToken,
          options: Options(receiveTimeout: receiveTimeout),
        ));
  }

  Future<dynamic> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) {
    return _send(() => _dio.post<dynamic>(
          path,
          data: data,
          cancelToken: cancelToken,
          options: Options(receiveTimeout: receiveTimeout),
        ));
  }

  Future<dynamic> put(
    String path, {
    Object? data,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) {
    return _send(() => _dio.put<dynamic>(
          path,
          data: data,
          cancelToken: cancelToken,
          options: Options(receiveTimeout: receiveTimeout),
        ));
  }

  Future<dynamic> delete(String path, {CancelToken? cancelToken}) {
    return _send(() => _dio.delete<dynamic>(path, cancelToken: cancelToken));
  }

  /// `GET /health` (unauthenticated). Returns true when the API is healthy.
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get<dynamic>(
        '/health',
        options: Options(
          extra: AuthInterceptor.skipAuth,
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final result = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      result[key] = value;
    });
    return result;
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
      headers: {'Accept': 'application/json, application/problem+json'},
    ),
  );
  dio.interceptors.add(AuthInterceptor(dio));
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestHeader: false,
        requestBody: true,
        responseHeader: false,
        responseBody: false,
        logPrint: (o) => debugPrint(o.toString()),
      ),
    );
  }
  ref.onDispose(dio.close);
  return dio;
});

/// Separate client for downloading files from signed URLs (no auth header,
/// long timeouts).
final downloadDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: const Duration(minutes: 15),
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(dioProvider)),
);
