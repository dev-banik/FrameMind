import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/history_repository.dart';
import '../data/models/chat_models.dart';

// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------

class HistoryFilterController extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() {
    ref.watch(currentUidProvider);
    return const HistoryFilter();
  }

  void setSearch(String search) {
    if (search == state.search) return;
    state = state.copyWith(search: search);
  }

  void apply(HistoryFilter filter) => state = filter;

  void clearFilters() => state = HistoryFilter(search: state.search);
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterController, HistoryFilter>(HistoryFilterController.new);

// ---------------------------------------------------------------------------
// Paginated history
// ---------------------------------------------------------------------------

class HistoryState {
  const HistoryState({
    required this.items,
    required this.page,
    required this.total,
    this.isLoadingMore = false,
    this.fromCache = false,
    this.loadMoreError,
  });

  final List<ChatSummary> items;
  final int page;
  final int total;
  final bool isLoadingMore;

  /// True when showing the offline Hive copy.
  final bool fromCache;
  final Object? loadMoreError;

  bool get hasMore => !fromCache && items.length < total;

  HistoryState copyWith({
    List<ChatSummary>? items,
    int? page,
    int? total,
    bool? isLoadingMore,
    Object? Function()? loadMoreError,
  }) =>
      HistoryState(
        items: items ?? this.items,
        page: page ?? this.page,
        total: total ?? this.total,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        fromCache: fromCache,
        loadMoreError: loadMoreError != null ? loadMoreError() : this.loadMoreError,
      );
}

class HistoryController extends AsyncNotifier<HistoryState> {
  HistoryRepository get _repo => ref.read(historyRepositoryProvider);

  @override
  Future<HistoryState> build() async {
    final uid = ref.watch(currentUidProvider);
    final filter = ref.watch(historyFilterProvider);
    if (uid == null) {
      return const HistoryState(items: [], page: 1, total: 0);
    }
    try {
      final page = await ref.read(historyRepositoryProvider).getHistory(
            filter: filter,
            page: 1,
            pageSize: AppConfig.historyPageSize,
          );
      return HistoryState(items: page.items, page: 1, total: page.total);
    } on ApiException catch (e) {
      if (e.isOffline) {
        final cached = ref.read(historyRepositoryProvider).cachedHistory();
        if (cached != null) {
          final items = cached.where(filter.matches).toList();
          return HistoryState(
            items: items,
            page: 1,
            total: items.length,
            fromCache: true,
          );
        }
      }
      rethrow;
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true, loadMoreError: () => null));
    try {
      final next = await _repo.getHistory(
        filter: ref.read(historyFilterProvider),
        page: current.page + 1,
        pageSize: AppConfig.historyPageSize,
      );
      final seen = current.items.map((c) => c.id).toSet();
      final merged = [
        ...current.items,
        ...next.items.where((c) => !seen.contains(c.id)),
      ];
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(
        items: merged,
        page: current.page + 1,
        total: next.items.isEmpty ? merged.length : next.total,
        isLoadingMore: false,
      ));
    } catch (e) {
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(isLoadingMore: false, loadMoreError: () => e));
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // Error is rendered from state.
    }
  }

  void removeLocal(String chatId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final items = current.items.where((c) => c.id != chatId).toList();
    if (items.length == current.items.length) return;
    state = AsyncData(current.copyWith(items: items, total: current.total - 1));
  }

  void replaceLocal(ChatSummary chat) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      items: [for (final c in current.items) c.id == chat.id ? chat : c],
    ));
  }
}

final historyControllerProvider =
    AsyncNotifierProvider<HistoryController, HistoryState>(HistoryController.new);

/// A handful of the newest chats for the Home screen.
final recentChatsProvider = FutureProvider.autoDispose<List<ChatSummary>>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const [];
  final repo = ref.watch(historyRepositoryProvider);
  try {
    final page = await repo.getHistory(page: 1, pageSize: 5);
    return page.items;
  } on ApiException catch (e) {
    if (e.isOffline) {
      final cached = repo.cachedHistory();
      if (cached != null) return cached.take(5).toList();
    }
    rethrow;
  }
});

// ---------------------------------------------------------------------------
// Single chat
// ---------------------------------------------------------------------------

class ChatController extends AutoDisposeFamilyAsyncNotifier<Chat, String> {
  @override
  Future<Chat> build(String arg) {
    ref.watch(currentUidProvider);
    return ref.read(historyRepositoryProvider).getChat(arg);
  }

  /// Replaces the chat with a fresh server copy (e.g. returned by a mutation).
  void setChat(Chat chat) {
    state = AsyncData(chat);
    ref.read(historyRepositoryProvider).cacheChat(chat);
  }

  Future<void> reload() async {
    final result = await AsyncValue.guard(
      () => ref.read(historyRepositoryProvider).getChat(arg),
    );
    // Keep showing old data if the refresh failed.
    if (result.hasError && state.hasValue) return;
    state = result;
  }
}

final chatControllerProvider =
    AsyncNotifierProvider.autoDispose.family<ChatController, Chat, String>(
  ChatController.new,
);
