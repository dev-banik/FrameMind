import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../data/models/script.dart';
import '../../providers/script_editor_controller.dart';

enum SceneMenuAction { regenerate, moveUp, moveDown, delete }

/// Editable scene: visual, narration, dialogues, camera direction, duration.
class SceneCard extends StatelessWidget {
  const SceneCard({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.enabled,
    required this.regenerating,
    required this.characterNames,
    required this.onChanged,
    required this.onAddDialogue,
    required this.onUpdateDialogue,
    required this.onRemoveDialogue,
    required this.onPickCharacter,
    required this.onMenu,
  });

  final EditableScene item;
  final int index;
  final int total;
  final bool enabled;
  final bool regenerating;
  final List<String> characterNames;
  final void Function(Scene Function(Scene scene) change) onChanged;
  final VoidCallback onAddDialogue;
  final void Function(int index, Dialogue dialogue) onUpdateDialogue;
  final void Function(int index) onRemoveDialogue;
  final void Function(int index, String name) onPickCharacter;
  final void Function(SceneMenuAction action) onMenu;

  String _key(String field) => 'scene-${item.id}-${item.revision}-$field';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scene = item.scene;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: regenerating ? scheme.primary : scheme.outlineVariant.withAlpha(120),
          width: regenerating ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (regenerating) const LinearProgressIndicator(minHeight: 3),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    regenerating ? 'Rewriting scene…' : 'Scene ${index + 1}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatDurationShort(scene.durationSeconds),
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                PopupMenuButton<SceneMenuAction>(
                  enabled: enabled,
                  tooltip: 'Scene actions',
                  onSelected: onMenu,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: SceneMenuAction.regenerate,
                      child: ListTile(
                        leading: Icon(Icons.auto_fix_high_rounded),
                        title: Text('Regenerate'),
                      ),
                    ),
                    PopupMenuItem(
                      value: SceneMenuAction.moveUp,
                      enabled: index > 0,
                      child: const ListTile(
                        leading: Icon(Icons.arrow_upward_rounded),
                        title: Text('Move up'),
                      ),
                    ),
                    PopupMenuItem(
                      value: SceneMenuAction.moveDown,
                      enabled: index < total - 1,
                      child: const ListTile(
                        leading: Icon(Icons.arrow_downward_rounded),
                        title: Text('Move down'),
                      ),
                    ),
                    PopupMenuItem(
                      value: SceneMenuAction.delete,
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
          AbsorbPointer(
            absorbing: !enabled,
            child: Opacity(
              opacity: enabled ? 1 : 0.6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: ValueKey(_key('visual')),
                      initialValue: scene.visual,
                      minLines: 2,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Visual',
                        prefixIcon: Icon(Icons.image_outlined),
                        alignLabelWithHint: true,
                      ),
                      onChanged: (v) => onChanged((s) => s.copyWith(visual: v)),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey(_key('narration')),
                      initialValue: scene.narration,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Narration',
                        prefixIcon: Icon(Icons.record_voice_over_outlined),
                        alignLabelWithHint: true,
                      ),
                      onChanged: (v) => onChanged((s) => s.copyWith(narration: v)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.forum_outlined, size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text('Dialogue', style: theme.textTheme.labelLarge),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: onAddDialogue,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add line'),
                        ),
                      ],
                    ),
                    if (scene.dialogues.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'No dialogue in this scene.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (var i = 0; i < scene.dialogues.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DialogueRow(
                          fieldKey: _key('dialogue-$i'),
                          dialogue: scene.dialogues[i],
                          characterNames: characterNames,
                          onChanged: (d) => onUpdateDialogue(i, d),
                          onRemove: () => onRemoveDialogue(i),
                          onPickCharacter: (name) => onPickCharacter(i, name),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey(_key('camera')),
                            initialValue: scene.cameraDirection,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Camera direction',
                              prefixIcon: Icon(Icons.videocam_outlined),
                            ),
                            onChanged: (v) => onChanged((s) => s.copyWith(cameraDirection: v)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 96,
                          child: TextFormField(
                            key: ValueKey(_key('duration')),
                            initialValue: scene.durationSeconds.toString(),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Secs',
                              suffixText: 's',
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null && n > 0) {
                                onChanged((s) => s.copyWith(durationSeconds: clampInt(n, 1, 300)));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogueRow extends StatelessWidget {
  const _DialogueRow({
    required this.fieldKey,
    required this.dialogue,
    required this.characterNames,
    required this.onChanged,
    required this.onRemove,
    required this.onPickCharacter,
  });

  final String fieldKey;
  final Dialogue dialogue;
  final List<String> characterNames;
  final ValueChanged<Dialogue> onChanged;
  final VoidCallback onRemove;
  final ValueChanged<String> onPickCharacter;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: TextFormField(
            key: ValueKey('$fieldKey-character'),
            initialValue: dialogue.character,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Character',
              isDense: true,
              suffixIcon: characterNames.isEmpty
                  ? null
                  : _CharacterPicker(
                      names: characterNames,
                      onPicked: onPickCharacter,
                    ),
              suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            onChanged: (v) => onChanged(dialogue.copyWith(character: v)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            key: ValueKey('$fieldKey-line'),
            initialValue: dialogue.line,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Line', isDense: true),
            onChanged: (v) => onChanged(dialogue.copyWith(line: v)),
          ),
        ),
        IconButton(
          tooltip: 'Remove line',
          onPressed: onRemove,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
      ],
    );
  }
}

/// Small dropdown to pick one of the script's characters. Picking one re-keys
/// the row (via the scene revision) so the text field shows the new name.
class _CharacterPicker extends StatelessWidget {
  const _CharacterPicker({required this.names, required this.onPicked});

  final List<String> names;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Pick character',
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
      onSelected: onPicked,
      itemBuilder: (context) => [
        for (final n in names) PopupMenuItem(value: n, child: Text(n)),
      ],
    );
  }
}
