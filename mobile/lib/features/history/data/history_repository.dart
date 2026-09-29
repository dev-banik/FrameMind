import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/hive_cache.dart';
import '../../../core/utils/json.dart';
import 'models/chat_models.dart';

/// Filter for `GET /history`.
class HistoryFilter {
  const HistoryFilter({
    this.search = '',
    this.language,
    this.status,
    this.projectId,
  });

  final String search;
  final Language? language;
  final ChatStatus? status;
  final String? projectId;

  bool get isEmpty =>
      search.trim().isEmpty && language == null && status == null && projectId == null;

  /// Number of non-search filters applied (for the filter button badge).
  int get activeFilterCount =>
      (language != null ? 1 : 0) + (status != null ? 1 : 0) + (projectId != null ? 1 : 0);

  HistoryFilter copyWith({
    String? search,
    Language? Function()? language,
    ChatStatus? Function()? status,
    String? Function()? projectId,
  }) =>
      HistoryFilter(
        search: search ?? this.search,
        language: language != null ? language() : this.language,
        status: status != null ? status() : this.status,
        projectId: projectId != null ? projectId() : this.projectId,
      );

  bool matches(ChatSummary chat) {
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty && !chat.title.toLowerCase().contains(q)) return false;
    if (language != null && chat.language != language) return false;
    if (status != null && chat.status != status) return false;
    if (projectId != null && chat.projectId != projectId) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryFilter &&
      other.search == search &&
      other.language == language &&
      other.status == status &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(search, language, status, projectId);
}

/// History + chat endpoints (`/history`, `/chat/*`) with offline caching.
class HistoryRepository {
  HistoryRepository(this._api, this._cache);

  final ApiClient _api;
  final HiveCache _cache;

  static const _recentKey = 'recent';
  static String _chatKey(String id) => 'chat:$id';

  /// `GET /history`
  Future<HistoryPage> getHistory({
    HistoryFilter filter = const HistoryFilter(),
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _api.get('/history', query: {
      'search': filter.search.trim(),
      'projectId': filter.projectId,
      'language': filter.language?.apiValue,
      'status': filter.status?.apiValue,
      'page': page,
      'pageSize': pageSize,
    });
    final result = HistoryPage.fromJson(asJsonMap(data));
    if (page == 1 && filter.isEmpty) {
      await _cache.putJson(
        HiveCache.historyBox,
        _recentKey,
        result.items.map((c) => c.toJson()).toList(),
      );
    }
    return result;
  }

  /// Most recent unfiltered first page, as last seen online.
  List<ChatSummary>? cachedHistory() {
    final cached = _cache.getJson(HiveCache.historyBox, _recentKey);
    if (cached == null) return null;
    return parseList(cached, ChatSummary.fromJson);
  }

  Future<void> removeFromCache(String chatId) async {
    final cached = cachedHistory();
    if (cached != null) {
      await _cache.putJson(
        HiveCache.historyBox,
        _recentKey,
        cached.where((c) => c.id != chatId).map((c) => c.toJson()).toList(),
      );
    }
    await _cache.remove(HiveCache.chatsBox, _chatKey(chatId));
  }

  /// `GET /chat/{id}` (falls back to the cached copy when offline).
  Future<Chat> getChat(String id) async {
    try {
      final data = await _api.get('/chat/$id');
      final chat = Chat.fromJson(asJsonMap(data));
      await cacheChat(chat);
      return chat;
    } on ApiException catch (e) {
      if (e.isOffline) {
        final cached = _cache.getJson(HiveCache.chatsBox, _chatKey(id));
        if (cached != null) return Chat.fromJson(asJsonMap(cached));
      }
      rethrow;
    }
  }

  Future<void> cacheChat(Chat chat) =>
      _cache.putJson(HiveCache.chatsBox, _chatKey(chat.id), chat.toJson());

  /// `PUT /chat/{id}/project`
  Future<void> moveToProject(String chatId, String? projectId) async {
    await _api.put('/chat/$chatId/project', data: {'projectId': projectId});
  }

  /// `POST /chat/{id}/duplicate`
  Future<Chat> duplicate(String chatId) async {
    final data = await _api.post('/chat/$chatId/duplicate');
    final chat = Chat.fromJson(asJsonMap(data));
    await cacheChat(chat);
    return chat;
  }

  /// `DELETE /chat/{id}`
  Future<void> delete(String chatId) async {
    await _api.delete('/chat/$chatId');
    await removeFromCache(chatId);
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(
    ref.watch(apiClientProvider),
    ref.watch(hiveCacheProvider),
  ),
);
