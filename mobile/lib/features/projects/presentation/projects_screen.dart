import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/state_views.dart';
import '../../history/providers/chat_list_refresh.dart';
import '../data/models/project.dart';
import '../providers/projects_providers.dart';

enum _ProjectMenu { rename, delete }

/// Shared project dialogs used by the list and the detail screen.
abstract final class ProjectDialogs {
  static Future<void> create(BuildContext context, WidgetRef ref) async {
    final name = await showTextInputDialog(
      context,
      title: 'New project',
      label: 'Project name',
      hint: 'e.g. Family Stories',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    try {
      await ref.read(projectsControllerProvider.notifier).create(name);
      showAppSnackBar('Project "$name" created');
    } catch (e) {
      showAppSnackBar(friendlyError(e), isError: true);
    }
  }

  static Future<void> rename(BuildContext context, WidgetRef ref, Project project) async {
    final name = await showTextInputDialog(
      context,
      title: 'Rename project',
      initialValue: project.name,
      label: 'Project name',
      confirmLabel: 'Rename',
    );
    if (name == null || name == project.name) return;
    try {
      await ref.read(projectsControllerProvider.notifier).rename(project.id, name);
      showAppSnackBar('Project renamed');
    } catch (e) {
      showAppSnackBar(friendlyError(e), isError: true);
    }
  }

  /// Returns true when the project was deleted.
  static Future<bool> delete(BuildContext context, WidgetRef ref, Project project) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete "${project.name}"?',
      message: 'The project will be deleted. Its chats are kept and moved to "No project".',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return false;
    try {
      await ref.read(projectsControllerProvider.notifier).delete(project.id);
      refreshChatLists(ref.invalidate);
      showAppSnackBar('Project deleted');
      return true;
    } catch (e) {
      showAppSnackBar(friendlyError(e), isError: true);
      return false;
    }
  }
}

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ProjectDialogs.create(context, ref),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New project'),
      ),
      body: projects.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(projectsControllerProvider),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.read(projectsControllerProvider.notifier).refresh(),
          child: list.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: EmptyView(
                        icon: Icons.folder_open_rounded,
                        title: 'No projects yet',
                        message: 'Group related video ideas into projects to keep them tidy.',
                        action: FilledButton.icon(
                          onPressed: () => ProjectDialogs.create(context, ref),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create project'),
                        ),
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _ProjectTile(project: list[index]),
                ),
        ),
      ),
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(AppRoutes.project(project.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.folder_rounded, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${project.chatCount} ${project.chatCount == 1 ? 'chat' : 'chats'}',
                        if (project.createdAt != null) 'Created ${formatDate(project.createdAt)}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_ProjectMenu>(
                tooltip: 'Project actions',
                onSelected: (action) {
                  switch (action) {
                    case _ProjectMenu.rename:
                      ProjectDialogs.rename(context, ref, project);
                    case _ProjectMenu.delete:
                      ProjectDialogs.delete(context, ref, project);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _ProjectMenu.rename,
                    child: ListTile(
                      leading: Icon(Icons.drive_file_rename_outline_rounded),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _ProjectMenu.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                      title: Text('Delete', style: TextStyle(color: scheme.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
