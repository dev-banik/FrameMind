import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/date_grouping.dart';
import '../../../core/widgets/state_views.dart';
import '../data/models/chat_models.dart';
import '../providers/history_providers.dart';
import 'widgets/chat_actions.dart';
import 'widgets/chat_list_tile.dart';
import 'widgets/history_filter_sheet.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _scrollController = ScrollController();
  late final TextEditingController _searchController =
      TextEditingController(text: ref.read(historyFilterProvider).search);
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(historyControllerProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(historyFilterProvider.notifier).setSearch(value.trim());
    });
    setState(() {}); // update clear button visibility
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(historyFilterProvider.notifier).setSearch('');
    setState(() {});
  }

  Future<void> _openFilters() async {
    final current = ref.read(historyFilterProvider);
    final result = await showHistoryFilterSheet(context, current);
    if (result != null) ref.read(historyFilterProvider.notifier).apply(result);
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyControllerProvider);
    final filter = ref.watch(historyFilterProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search your chats',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _clearSearch,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Filter',
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: filter.activeFilterCount > 0,
                    label: Text('${filter.activeFilterCount}'),
                    child: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: history.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(historyControllerProvider),
        ),
        data: (state) {
          final content = _HistoryList(
            state: state,
            filterActive: !filter.isEmpty,
            scrollController: _scrollController,
            onClearFilters: () {
              _clearSearch();
              ref.read(historyFilterProvider.notifier).clearFilters();
            },
          );
          return RefreshIndicator(
            onRefresh: () => ref.read(historyControllerProvider.notifier).refresh(),
            child: state.fromCache
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: InfoBanner(
                          icon: Icons.cloud_off_rounded,
                          message: "You're offline - showing saved history.",
                          action: TextButton(
                            onPressed: () => ref.invalidate(historyControllerProvider),
                            child: Text(
                              'Retry',
                              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: content),
                    ],
                  )
                : content,
          );
        },
      ),
    );
  }
}

/// A flattened list of section headers and chat rows.
sealed class _Row {}

class _HeaderRow extends _Row {
  _HeaderRow(this.group);
  final DateGroup group;
}

class _ChatRow extends _Row {
  _ChatRow(this.chat, this.group);
  final ChatSummary chat;
  final DateGroup group;
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({
    required this.state,
    required this.filterActive,
    required this.scrollController,
    required this.onClearFilters,
  });

  final HistoryState state;
  final bool filterActive;
  final ScrollController scrollController;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (state.items.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: filterActive
                ? EmptyView(
                    icon: Icons.search_off_rounded,
                    title: 'No matching chats',
                    message: 'Try a different search or clear the filters.',
                    action: OutlinedButton(
                      onPressed: onClearFilters,
                      child: const Text('Clear filters'),
                    ),
                  )
                : EmptyView(
                    icon: Icons.history_rounded,
                    title: 'No history yet',
                    message: 'Every video idea you create is saved here.',
                    action: FilledButton(
                      onPressed: () => context.go(AppRoutes.home),
                      child: const Text('Create something'),
                    ),
                  ),
          ),
        ),
      );
    }

    final groups = groupByDate(state.items, (c) => c.createdAt);
    final rows = <_Row>[
      for (final entry in groups.entries) ...[
        _HeaderRow(entry.key),
        for (final chat in entry.value) _ChatRow(chat, entry.key),
      ],
    ];
    return ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == rows.length) {
          return _Footer(state: state);
        }
        final row = rows[index];
        return switch (row) {
          _HeaderRow(:final group) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(
                group.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          _ChatRow(:final chat, :final group) => Dismissible(
              key: ValueKey('history-${chat.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                color: theme.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Icon(Icons.delete_outline_rounded,
                    color: theme.colorScheme.onErrorContainer),
              ),
              confirmDismiss: (_) => ChatActions.delete(context, ref, chat),
              child: ChatListTile(
                chat: chat,
                showTime: group == DateGroup.today || group == DateGroup.yesterday,
                onTap: () => ChatActions.open(context, chat.id),
                trailing: ChatActionsMenu(chat: chat),
              ),
            ),
        };
      },
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final HistoryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(friendlyError(state.loadMoreError), textAlign: TextAlign.center),
            TextButton(
              onPressed: () => ref.read(historyControllerProvider.notifier).loadMore(),
              child: const Text('Load more'),
            ),
          ],
        ),
      );
    }
    if (state.hasMore) {
      // Scroll listener triggers loading; offer a manual fallback too.
      return Center(
        child: TextButton(
          onPressed: () => ref.read(historyControllerProvider.notifier).loadMore(),
          child: const Text('Load more'),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}
