import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Attaches the Firebase ID token to every request and, on a 401, forces a
/// token refresh and retries the request exactly once.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio);

  final Dio _dio;

  static const _retriedKey = 'fm_auth_retried';
  static const _skipAuthKey = 'fm_skip_auth';

  /// Pass `Options(extra: AuthInterceptor.skipAuth)` for unauthenticated calls.
  static const Map<String, dynamic> skipAuth = {_skipAuthKey: true};

  User? get _user {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      // Firebase not initialised yet.
      return null;
    }
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_skipAuthKey] == true) {
      handler.next(options);
      return;
    }
    final user = _user;
    if (user != null) {
      try {
        final token = await user.getIdToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      } catch (e) {
        debugPrint('AuthInterceptor: failed to get ID token: $e');
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final user = _user;
    final shouldRetry = err.response?.statusCode == 401 &&
        options.extra[_retriedKey] != true &&
        options.extra[_skipAuthKey] != true;

    if (!shouldRetry || user == null) {
      handler.next(err);
      return;
    }

    try {
      final freshToken = await user.getIdToken(true);
      options.extra[_retriedKey] = true;
      if (freshToken != null) {
        options.headers['Authorization'] = 'Bearer $freshToken';
      }
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (_) {
      handler.next(err);
    }
  }
}
