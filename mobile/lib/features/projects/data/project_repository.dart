import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/hive_cache.dart';
import '../../../core/utils/json.dart';
import 'models/project.dart';

/// `/project` endpoints with an offline Hive copy of the project list and
/// project details.
class ProjectRepository {
  ProjectRepository(this._api, this._cache);

  final ApiClient _api;
  final HiveCache _cache;

  static const _listKey = 'list';
  static String _detailKey(String id) => 'detail:$id';

  /// `GET /project` (falls back to the cached copy when offline).
  Future<List<Project>> list() async {
    try {
      final data = await _api.get('/project');
      final projects = parseList(data, Project.fromJson);
      await _cache.putJson(
        HiveCache.projectsBox,
        _listKey,
        projects.map((p) => p.toJson()).toList(),
      );
      return projects;
    } on ApiException catch (e) {
      if (e.isOffline) {
        final cached = _cache.getJson(HiveCache.projectsBox, _listKey);
        if (cached != null) return parseList(cached, Project.fromJson);
      }
      rethrow;
    }
  }

  /// `GET /project/{id}` (falls back to the cached copy when offline).
  Future<ProjectDetail> get(String id) async {
    try {
      final data = await _api.get('/project/$id');
      final detail = ProjectDetail.fromJson(asJsonMap(data));
      await _cache.putJson(HiveCache.projectsBox, _detailKey(id), detail.toJson());
      return detail;
    } on ApiException catch (e) {
      if (e.isOffline) {
        final cached = _cache.getJson(HiveCache.projectsBox, _detailKey(id));
        if (cached != null) return ProjectDetail.fromJson(asJsonMap(cached));
      }
      rethrow;
    }
  }

  /// `POST /project`
  Future<Project> create(String name) async {
    final data = await _api.post('/project', data: {'name': name});
    return Project.fromJson(asJsonMap(data));
  }

  /// `PUT /project/{id}`
  Future<Project> rename(String id, String name) async {
    final data = await _api.put('/project/$id', data: {'name': name});
    return Project.fromJson(asJsonMap(data));
  }

  /// `DELETE /project/{id}` - chats are kept and moved to "no project".
  Future<void> delete(String id) async {
    await _api.delete('/project/$id');
    await _cache.remove(HiveCache.projectsBox, _detailKey(id));
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(
    ref.watch(apiClientProvider),
    ref.watch(hiveCacheProvider),
  ),
);
