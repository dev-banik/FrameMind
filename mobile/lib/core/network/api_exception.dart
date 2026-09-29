import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/json.dart';

enum ApiErrorKind {
  network,
  timeout,
  cancelled,
  validation,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  server,
  unknown,
}

/// Typed error for every failed API call. [message] is always safe to show
/// to the user.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.title,
    this.detail,
    this.fieldErrors = const {},
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? title;
  final String? detail;
  final Map<String, List<String>> fieldErrors;

  bool get isOffline =>
      kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  bool get isCancelled => kind == ApiErrorKind.cancelled;

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          kind: ApiErrorKind.timeout,
          message: 'The server is taking too long to respond. Please try again.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          kind: ApiErrorKind.network,
          message: "You're offline or the server can't be reached. Check your connection.",
        );
      case DioExceptionType.cancel:
        return const ApiException(
          kind: ApiErrorKind.cancelled,
          message: 'Request cancelled.',
        );
      case DioExceptionType.badCertificate:
        return const ApiException(
          kind: ApiErrorKind.network,
          message: 'Secure connection failed.',
        );
      case DioExceptionType.badResponse:
        return ApiException.fromResponse(error.response);
      case DioExceptionType.unknown:
        final inner = error.error;
        if (inner != null && inner.toString().contains('SocketException')) {
          return const ApiException(
            kind: ApiErrorKind.network,
            message: "You're offline or the server can't be reached. Check your connection.",
          );
        }
        if (error.response != null) {
          return ApiException.fromResponse(error.response);
        }
        return ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Something went wrong. Please try again.',
          detail: error.message,
        );
    }
  }

  /// Parses an RFC 7807 problem+json body (`{ title, status, detail, errors }`).
  factory ApiException.fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    var data = response?.data;
    if (data is String && data.trim().startsWith('{')) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    final body = asJsonMap(data);
    final title = asStringOrNull(body['title']);
    final detail = asStringOrNull(body['detail']);
    final fieldErrors = <String, List<String>>{};
    final rawErrors = body['errors'];
    if (rawErrors is Map) {
      rawErrors.forEach((key, value) {
        final list = value is List
            ? value.map((e) => e.toString()).toList()
            : <String>[value.toString()];
        fieldErrors[key.toString()] = list;
      });
    }

    final kind = _kindFor(status);
    return ApiException(
      kind: kind,
      statusCode: status,
      title: title,
      detail: detail,
      fieldErrors: fieldErrors,
      message: _friendlyMessage(kind, title, detail, fieldErrors),
    );
  }

  static ApiErrorKind _kindFor(int? status) {
    switch (status) {
      case 400:
      case 422:
        return ApiErrorKind.validation;
      case 401:
        return ApiErrorKind.unauthorized;
      case 403:
        return ApiErrorKind.forbidden;
      case 404:
        return ApiErrorKind.notFound;
      case 409:
        return ApiErrorKind.conflict;
      case 429:
        return ApiErrorKind.rateLimited;
    }
    if (status != null && status >= 500) return ApiErrorKind.server;
    return ApiErrorKind.unknown;
  }

  static String _friendlyMessage(
    ApiErrorKind kind,
    String? title,
    String? detail,
    Map<String, List<String>> fieldErrors,
  ) {
    final text = '${title ?? ''} ${detail ?? ''}'.toLowerCase();
    switch (kind) {
      case ApiErrorKind.rateLimited:
        if (text.contains('daily') || text.contains('quota') || text.contains('limit')) {
          return "Daily limit reached. You've used all of today's videos - "
              'upgrade to Premium or try again tomorrow.';
        }
        return "You're going a bit fast - please slow down and try again in a moment.";
      case ApiErrorKind.forbidden:
        if (text.contains('1080') || text.contains('resolution') || text.isEmpty ||
            text.trim() == 'forbidden') {
          return 'Upgrade to Premium for 1080p videos.';
        }
        return detail ?? 'Upgrade to Premium to unlock this feature.';
      case ApiErrorKind.validation:
        if (fieldErrors.isNotEmpty) {
          final first = fieldErrors.values.firstWhere(
            (v) => v.isNotEmpty,
            orElse: () => const [],
          );
          if (first.isNotEmpty) return first.first;
        }
        return detail ?? title ?? 'Please check your input and try again.';
      case ApiErrorKind.unauthorized:
        return 'Your session has expired. Please sign in again.';
      case ApiErrorKind.notFound:
        return detail ?? "We couldn't find that. It may have been deleted.";
      case ApiErrorKind.conflict:
        return detail ?? "That action isn't available right now.";
      case ApiErrorKind.server:
        return 'Something went wrong on our side. Please try again shortly.';
      case ApiErrorKind.network:
      case ApiErrorKind.timeout:
      case ApiErrorKind.cancelled:
      case ApiErrorKind.unknown:
        return detail ?? title ?? 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() => 'ApiException($statusCode, $kind): $message';
}

/// Returns a user-friendly message for any error thrown in the app.
String friendlyError(Object? error) {
  if (error == null) return 'Something went wrong.';
  if (error is ApiException) return error.message;
  if (error is DioException) return ApiException.fromDio(error).message;
  if (error is AppException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// Base class for non-HTTP errors that carry a user-facing message.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}
