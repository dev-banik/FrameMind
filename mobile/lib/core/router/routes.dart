import '../models/enums.dart';

/// Route paths. Chat flow screens live outside the bottom-navigation shell.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String home = '/home';
  static const String history = '/history';
  static const String projects = '/projects';
  static const String profile = '/profile';

  static String project(String id) => '/projects/$id';

  /// Resolves the right screen from the chat's status.
  static String chat(String id) => '/chat/$id';
  static String analysis(String id) => '/chat/$id/analysis';
  static String config(String id) => '/chat/$id/config';
  static String script(String id) => '/chat/$id/script';

  static String generation(String id, {String? jobId, Resolution? resolution}) {
    final query = <String, String>{
      if (jobId != null && jobId.isNotEmpty) 'jobId': jobId,
      if (resolution != null) 'resolution': resolution.apiValue,
    };
    return Uri(path: '/chat/$id/generation', queryParameters: query.isEmpty ? null : query)
        .toString();
  }

  static String preview(String id, {String? videoId}) {
    return Uri(
      path: '/chat/$id/preview',
      queryParameters: videoId != null && videoId.isNotEmpty ? {'videoId': videoId} : null,
    ).toString();
  }
}
