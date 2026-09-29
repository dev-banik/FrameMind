import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/url_utils.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/badges.dart';
import '../../analysis/providers/analyze_controller.dart';
import '../../history/presentation/widgets/chat_actions.dart';
import '../../history/presentation/widgets/chat_list_tile.dart';
import '../../history/providers/chat_list_refresh.dart';
import '../../history/providers/history_providers.dart';
import '../../projects/data/models/project.dart';
import '../../projects/providers/projects_providers.dart';
import 'widgets/quota_chip.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _promptController = TextEditingController();
  SourcePlatform? _platform;
  String? _projectId;
  bool _showPrompt = false;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final text = _urlController.text.trim();
    final platform = parseVideoUrl(text) == null ? null : detectPlatform(text);
    if (platform != _platform) setState(() => _platform = platform);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your clipboard is empty')),
      );
      return;
    }
    _urlController.text = text;
    _urlController.selection = TextSelection.collapsed(offset: text.length);
    _formKey.currentState?.validate();
  }

  Future<void> _analyze() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uri = parseVideoUrl(_urlController.text)!;

    final result = await ref.read(analyzeControllerProvider.notifier).analyze(
          videoUrl: uri.toString(),
          projectId: _projectId,
          userPrompt: _promptController.text,
        );
    if (!mounted) return;

    if (result == null) {
      final error = ref.read(analyzeControllerProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
      return;
    }

    refreshChatLists(ref.invalidate);
    _urlController.clear();
    _promptController.clear();
    setState(() => _showPrompt = false);
    ref.read(analyzeControllerProvider.notifier).reset();
    context.push(AppRoutes.analysis(result.chatId));
  }

  Future<void> _refresh() async {
    refreshChatListsAndQuota(ref.invalidate);
    try {
      await ref.read(recentChatsProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analyzing = ref.watch(analyzeControllerProvider).isLoading;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      const AppWordmark(logoSize: 34),
                      const Spacer(),
                      QuotaChip(onTap: () => context.go(AppRoutes.profile)),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What inspires you today?',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Paste a YouTube, Facebook, Instagram or TikTok link. We learn its '
                        'style and mood, then write something completely new.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildInputCard(context, analyzing),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              const SliverToBoxAdapter(child: _RecentProjectsSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              const SliverToBoxAdapter(child: _RecentChatsSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard(BuildContext context, bool analyzing) {
    final theme = Theme.of(context);
    final projects = ref.watch(projectsControllerProvider).valueOrNull ?? const <Project>[];
    final platform = _platform;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(120)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _urlController,
                enabled: !analyzing,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onFieldSubmitted: (_) => _analyze(),
                validator: validateVideoUrl,
                decoration: InputDecoration(
                  hintText: 'https://youtu.be/…',
                  labelText: 'Video link',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: platform == null
                        ? const Icon(Icons.link_rounded)
                        : PlatformIcon(platform: platform),
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton.icon(
                      onPressed: analyzing ? null : _paste,
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      label: const Text('Paste'),
                    ),
                  ),
                  helperText: platform == null
                      ? null
                      : platform == SourcePlatform.other
                          ? "Unrecognised platform - we'll do our best"
                          : '${platform.label} video detected',
                ),
              ),
              const SizedBox(height: 8),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState:
                    _showPrompt ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: analyzing ? null : () => setState(() => _showPrompt = true),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Add extra direction (optional)'),
                  ),
                ),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: TextField(
                    controller: _promptController,
                    enabled: !analyzing,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Extra direction',
                      hintText: 'e.g. Make it about a grandfather and his dog, set in a village',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ),
              if (projects.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  value: projects.any((p) => p.id == _projectId) ? _projectId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Save to project',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No project')),
                    for (final p in projects)
                      DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: analyzing ? null : (value) => setState(() => _projectId = value),
                ),
                const SizedBox(height: 12),
              ],
              _AnalyzeButton(analyzing: analyzing, onPressed: _analyze),
              if (analyzing) ...[
                const SizedBox(height: 10),
                Text(
                  'Studying category, theme, mood, style and pace… this can take up to a minute.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyzeButton extends StatelessWidget {
  const _AnalyzeButton({required this.analyzing, required this.onPressed});

  final bool analyzing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: analyzing ? null : AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: analyzing ? null : Colors.transparent,
          shadowColor: Colors.transparent,
        ),
        onPressed: analyzing ? null : onPressed,
        icon: analyzing
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : const Icon(Icons.auto_awesome_rounded),
        label: Text(analyzing ? 'Analyzing…' : 'Analyze video'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ],
      ),
    );
  }
}

class _RecentProjectsSection extends ConsumerWidget {
  const _RecentProjectsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsControllerProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Recent projects',
          onSeeAll: () => context.go(AppRoutes.projects),
        ),
        SizedBox(
          height: 104,
          child: projects.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(projectsControllerProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Couldn't load projects - retry"),
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ProjectCard(
                    icon: Icons.create_new_folder_outlined,
                    title: 'Create a project',
                    subtitle: 'Group related ideas',
                    onTap: () => context.go(AppRoutes.projects),
                  ),
                );
              }
              final items = list.take(10).toList();
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final project = items[index];
                  return _ProjectCard(
                    icon: Icons.folder_rounded,
                    title: project.name,
                    subtitle:
                        '${project.chatCount} ${project.chatCount == 1 ? 'chat' : 'chats'}',
                    color: theme.colorScheme.primary,
                    onTap: () => context.go(AppRoutes.project(project.id)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Material(
        color: theme.colorScheme.secondaryContainer.withAlpha(150),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color ?? theme.colorScheme.onSecondaryContainer),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentChatsSection extends ConsumerWidget {
  const _RecentChatsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(recentChatsProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Recent chats',
          onSeeAll: () => context.go(AppRoutes.history),
        ),
        chats.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(friendlyError(e), textAlign: TextAlign.center),
                TextButton.icon(
                  onPressed: () => ref.invalidate(recentChatsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.movie_filter_outlined, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your generations will appear here. Paste a link above to start.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final chat in list)
                  ChatListTile(
                    chat: chat,
                    onTap: () => ChatActions.open(context, chat.id),
                    trailing: ChatActionsMenu(chat: chat),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
