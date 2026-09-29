import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/models/project.dart';
import '../data/project_repository.dart';

class ProjectsController extends AsyncNotifier<List<Project>> {
  ProjectRepository get _repo => ref.read(projectRepositoryProvider);

  @override
  Future<List<Project>> build() async {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const [];
    return ref.read(projectRepositoryProvider).list();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {}
  }

  Future<Project> create(String name) async {
    final project = await _repo.create(name);
    final current = state.valueOrNull ?? const <Project>[];
    state = AsyncData([project, ...current]);
    return project;
  }

  Future<void> rename(String id, String name) async {
    final updated = await _repo.rename(id, name);
    final current = state.valueOrNull ?? const <Project>[];
    state = AsyncData([
      for (final p in current)
        p.id == id ? updated.copyWith(chatCount: p.chatCount) : p,
    ]);
    ref.invalidate(projectDetailProvider(id));
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    final current = state.valueOrNull ?? const <Project>[];
    state = AsyncData(current.where((p) => p.id != id).toList());
  }
}

final projectsControllerProvider =
    AsyncNotifierProvider<ProjectsController, List<Project>>(ProjectsController.new);

final projectDetailProvider =
    FutureProvider.autoDispose.family<ProjectDetail, String>((ref, id) async {
  ref.watch(currentUidProvider);
  return ref.watch(projectRepositoryProvider).get(id);
});
