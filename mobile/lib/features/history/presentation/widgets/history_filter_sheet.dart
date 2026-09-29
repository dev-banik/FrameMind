import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../projects/providers/projects_providers.dart';
import '../../data/history_repository.dart';

/// Filter by language, status and project. Returns the new filter or null.
Future<HistoryFilter?> showHistoryFilterSheet(
  BuildContext context,
  HistoryFilter current,
) {
  return showModalBottomSheet<HistoryFilter>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _HistoryFilterSheet(initial: current),
  );
}

class _HistoryFilterSheet extends ConsumerStatefulWidget {
  const _HistoryFilterSheet({required this.initial});

  final HistoryFilter initial;

  @override
  ConsumerState<_HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends ConsumerState<_HistoryFilterSheet> {
  late Language? _language = widget.initial.language;
  late ChatStatus? _status = widget.initial.status;
  late String? _projectId = widget.initial.projectId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = ref.watch(projectsControllerProvider).valueOrNull ?? const [];

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(title, style: theme.textTheme.titleSmall),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filter history', style: theme.textTheme.titleLarge),
            section('Language'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Any'),
                  selected: _language == null,
                  onSelected: (_) => setState(() => _language = null),
                ),
                for (final l in Language.values)
                  ChoiceChip(
                    label: Text(l.apiValue),
                    selected: _language == l,
                    onSelected: (_) => setState(() => _language = l),
                  ),
              ],
            ),
            section('Status'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Any'),
                  selected: _status == null,
                  onSelected: (_) => setState(() => _status = null),
                ),
                for (final s in ChatStatus.filterable)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            section('Project'),
            DropdownButtonFormField<String?>(
              value: projects.any((p) => p.id == _projectId) ? _projectId : null,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.folder_outlined)),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All projects')),
                for (final p in projects)
                  DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(
                      HistoryFilter(search: widget.initial.search),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      HistoryFilter(
                        search: widget.initial.search,
                        language: _language,
                        status: _status,
                        projectId: _projectId,
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
