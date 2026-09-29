import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../../history/data/models/chat_models.dart';
import '../../history/presentation/widgets/chat_actions.dart';
import '../../history/presentation/widgets/chat_list_tile.dart';
import '../data/models/project.dart';
import '../providers/projects_providers.dart';
import 'projects_screen.dart';

/// A project's chats with Chats / Scripts / Videos tabs.
class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(projectDetailProvider(projectId));
    final name = detail.valueOrNull?.name;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name ?? 'Project'),
          actions: [
            if (detail.valueOrNull != null)
              PopupMenuButton<String>(
                onSelected: (value) async {
                  final d = detail.valueOrNull;
                  if (d == null) return;
                  final project = Project(
                    id: d.id,
                    name: d.name,
                    chatCount: d.chats.length,
                    createdAt: d.createdAt,
                  );
                  if (value == 'rename') {
                    await ProjectDialogs.rename(context, ref, project);
                  } else if (value == 'delete') {
                    final deleted = await ProjectDialogs.delete(context, ref, project);
                    if (deleted && context.mounted) context.go(AppRoutes.projects);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.drive_file_rename_outline_rounded),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Delete project'),
                    ),
                  ),
                ],
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chats'),
              Tab(text: 'Scripts'),
              Tab(text: 'Videos'),
            ],
          ),
        ),
        body: detail.when(
          skipLoadingOnRefresh: true,
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(projectDetailProvider(projectId)),
          ),
          data: (d) {
            final chats = d.chats;
            // Scripts: anything past the analysis step. Videos: has a video.
            final scripts = chats.where((c) => c.status != ChatStatus.analyzed).toList();
            final videos = chats.where((c) => c.hasVideo).toList();
            Future<void> refresh() async {
              ref.invalidate(projectDetailProvider(projectId));
              try {
                await ref.read(projectDetailProvider(projectId).future);
              } catch (_) {}
            }

            return TabBarView(
              children: [
                _ChatTab(
                  chats: chats,
                  onRefresh: refresh,
                  header: d.createdAt != null
                      ? 'Created ${formatDate(d.createdAt)} · ${chats.length} chats'
                      : '${chats.length} chats',
                  emptyIcon: Icons.chat_bubble_outline_rounded,
                  emptyTitle: 'No chats in this project',
                  emptyMessage:
                      'Pick this project on Home before analyzing, or move chats here from History.',
                ),
                _ChatTab(
                  chats: scripts,
                  onRefresh: refresh,
                  emptyIcon: Icons.description_outlined,
                  emptyTitle: 'No scripts yet',
                  emptyMessage: 'Scripts you generate in this project appear here.',
                ),
                _ChatTab(
                  chats: videos,
                  onRefresh: refresh,
                  emptyIcon: Icons.movie_outlined,
                  emptyTitle: 'No videos yet',
                  emptyMessage: 'Finished videos in this project appear here.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChatTab extends ConsumerWidget {
  const _ChatTab({
    required this.chats,
    required this.onRefresh,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    this.header,
  });

  final List<ChatSummary> chats;
  final Future<void> Function() onRefresh;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final String? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: chats.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: EmptyView(icon: emptyIcon, title: emptyTitle, message: emptyMessage),
                ),
              ),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              itemCount: chats.length + (header != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (header != null) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Text(
                        header!,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  index -= 1;
                }
                final chat = chats[index];
                return ChatListTile(
                  chat: chat,
                  onTap: () => ChatActions.open(context, chat.id),
                  trailing: ChatActionsMenu(chat: chat),
                );
              },
            ),
    );
  }
}
