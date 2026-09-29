import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../generation/data/generation_repository.dart';
import '../../generation/data/models/generation_models.dart';
import '../../history/data/models/chat_models.dart';
import '../../history/providers/history_providers.dart';
import '../data/models/script.dart';
import '../data/script_repository.dart';

class ScriptMissingException extends AppException {
  const ScriptMissingException()
      : super('No script has been generated for this video yet.');
}

enum ScriptBusy { none, saving, regeneratingAll, regeneratingScene, startingVideo }

/// A scene plus a stable local id (for widget keys) and a revision that is
/// bumped whenever its dialogue list changes shape.
class EditableScene {
  const EditableScene({required this.id, required this.scene, this.revision = 0});

  final int id;
  final Scene scene;
  final int revision;

  EditableScene copyWith({Scene? scene, int? revision}) => EditableScene(
        id: id,
        scene: scene ?? this.scene,
        revision: revision ?? this.revision,
      );
}

class ScriptEditorState {
  const ScriptEditorState({
    required this.chatId,
    required this.title,
    required this.summary,
    required this.characters,
    required this.scenes,
    required this.revision,
    this.dirty = false,
    this.restoredFromDraft = false,
    this.busy = ScriptBusy.none,
    this.busySceneId,
  });

  final String chatId;
  final String title;
  final String summary;
  final List<ScriptCharacter> characters;
  final List<EditableScene> scenes;

  /// Changes whenever the content is replaced wholesale (server copy).
  final int revision;

  /// True when there are edits not yet saved to the server.
  final bool dirty;
  final bool restoredFromDraft;
  final ScriptBusy busy;
  final int? busySceneId;

  bool get isBusy => busy != ScriptBusy.none;

  int get totalDurationSeconds =>
      scenes.fold(0, (sum, s) => sum + s.scene.durationSeconds);

  Script toScript() => Script(
        title: title.trim(),
        summary: summary.trim(),
        characters: characters,
        scenes: [
          for (var i = 0; i < scenes.length; i++) scenes[i].scene.copyWith(number: i + 1),
        ],
      );

  ScriptEditorState copyWith({
    String? title,
    String? summary,
    List<EditableScene>? scenes,
    bool? dirty,
    bool? restoredFromDraft,
    ScriptBusy? busy,
    int? Function()? busySceneId,
  }) =>
      ScriptEditorState(
        chatId: chatId,
        title: title ?? this.title,
        summary: summary ?? this.summary,
        characters: characters,
        scenes: scenes ?? this.scenes,
        revision: revision,
        dirty: dirty ?? this.dirty,
        restoredFromDraft: restoredFromDraft ?? this.restoredFromDraft,
        busy: busy ?? this.busy,
        busySceneId: busySceneId != null ? busySceneId() : this.busySceneId,
      );
}

/// Local, editable copy of a chat's script. Edits are auto-cached to Hive
/// (debounced) so nothing is lost offline; "Save Draft" pushes them to the API.
class ScriptEditorController
    extends AutoDisposeFamilyAsyncNotifier<ScriptEditorState, String> {
  static int _idSeed = 0;
  static int _nextId() => ++_idSeed;

  Timer? _draftTimer;
  Script? _pendingDraft;

  ScriptRepository get _repo => ref.read(scriptRepositoryProvider);

  @override
  Future<ScriptEditorState> build(String arg) async {
    final repo = ref.watch(scriptRepositoryProvider);
    ref.onDispose(() {
      _draftTimer?.cancel();
      final pending = _pendingDraft;
      _pendingDraft = null;
      if (pending != null) repo.saveLocalDraft(arg, pending);
    });

    final chat = await ref.watch(chatControllerProvider(arg).future);
    return _stateFromChat(chat, repo);
  }

  ScriptEditorState _stateFromChat(Chat chat, ScriptRepository repo) {
    final serverScript = chat.script;
    final draft = repo.loadLocalDraft(chat.id);
    final draftIsNewer = draft != null &&
        (chat.updatedAt == null || draft.savedAt.isAfter(chat.updatedAt!));

    if (draftIsNewer) {
      return _fromScript(chat.id, draft.script, dirty: true, restored: true);
    }
    if (serverScript == null) throw const ScriptMissingException();
    return _fromScript(chat.id, serverScript);
  }

  ScriptEditorState _fromScript(
    String chatId,
    Script script, {
    bool dirty = false,
    bool restored = false,
  }) {
    final ordered = [...script.scenes]..sort((a, b) => a.number.compareTo(b.number));
    return ScriptEditorState(
      chatId: chatId,
      title: script.title,
      summary: script.summary,
      characters: script.characters,
      scenes: [for (final s in ordered) EditableScene(id: _nextId(), scene: s)],
      revision: _nextId(),
      dirty: dirty,
      restoredFromDraft: restored,
    );
  }

  // ---- Local edits ----------------------------------------------------------

  void _edit(ScriptEditorState Function(ScriptEditorState current) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = change(current).copyWith(dirty: true);
    state = AsyncData(next);
    _scheduleDraft(next);
  }

  void _scheduleDraft(ScriptEditorState s) {
    _pendingDraft = s.toScript();
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), () {
      final pending = _pendingDraft;
      _pendingDraft = null;
      if (pending != null) _repo.saveLocalDraft(arg, pending);
    });
  }

  List<EditableScene> _mapScene(
    List<EditableScene> scenes,
    int id,
    EditableScene Function(EditableScene s) change,
  ) =>
      [for (final s in scenes) s.id == id ? change(s) : s];

  void setTitle(String value) => _edit((s) => s.copyWith(title: value));

  void setSummary(String value) => _edit((s) => s.copyWith(summary: value));

  void updateScene(int id, Scene Function(Scene scene) change) => _edit(
        (s) => s.copyWith(
          scenes: _mapScene(s.scenes, id, (e) => e.copyWith(scene: change(e.scene))),
        ),
      );

  void addScene() => _edit(
        (s) => s.copyWith(scenes: [
          ...s.scenes,
          EditableScene(
            id: _nextId(),
            scene: Scene(number: s.scenes.length + 1, durationSeconds: 5),
          ),
        ]),
      );

  void deleteScene(int id) =>
      _edit((s) => s.copyWith(scenes: s.scenes.where((e) => e.id != id).toList()));

  void moveScene(int id, int delta) => _edit((s) {
        final list = [...s.scenes];
        final index = list.indexWhere((e) => e.id == id);
        final target = index + delta;
        if (index < 0 || target < 0 || target >= list.length) return s;
        final item = list.removeAt(index);
        list.insert(target, item);
        return s.copyWith(scenes: list);
      });

  void addDialogue(int sceneId) => _edit((s) {
        final defaultCharacter = s.characters.isNotEmpty ? s.characters.first.name : '';
        return s.copyWith(
          scenes: _mapScene(
            s.scenes,
            sceneId,
            (e) => e.copyWith(
              revision: e.revision + 1,
              scene: e.scene.copyWith(dialogues: [
                ...e.scene.dialogues,
                Dialogue(character: defaultCharacter, line: ''),
              ]),
            ),
          ),
        );
      });

  void updateDialogue(int sceneId, int index, Dialogue dialogue) => _edit(
        (s) => s.copyWith(
          scenes: _mapScene(s.scenes, sceneId, (e) {
            if (index < 0 || index >= e.scene.dialogues.length) return e;
            final list = [...e.scene.dialogues];
            list[index] = dialogue;
            return e.copyWith(scene: e.scene.copyWith(dialogues: list));
          }),
        ),
      );

  /// Sets a dialogue's character from the picker (re-keys the row's fields).
  void setDialogueCharacter(int sceneId, int index, String name) => _edit(
        (s) => s.copyWith(
          scenes: _mapScene(s.scenes, sceneId, (e) {
            if (index < 0 || index >= e.scene.dialogues.length) return e;
            final list = [...e.scene.dialogues];
            list[index] = list[index].copyWith(character: name);
            return e.copyWith(
              revision: e.revision + 1,
              scene: e.scene.copyWith(dialogues: list),
            );
          }),
        ),
      );

  void removeDialogue(int sceneId, int index) => _edit(
        (s) => s.copyWith(
          scenes: _mapScene(s.scenes, sceneId, (e) {
            if (index < 0 || index >= e.scene.dialogues.length) return e;
            final list = [...e.scene.dialogues]..removeAt(index);
            return e.copyWith(
              revision: e.revision + 1,
              scene: e.scene.copyWith(dialogues: list),
            );
          }),
        ),
      );

  /// Drops local edits and reloads the server copy.
  Future<void> discardLocalChanges() async {
    await _discardLocalDraft();
    ref.invalidateSelf();
  }

  // ---- Server actions -------------------------------------------------------

  void _setBusy(ScriptBusy busy, {int? sceneId}) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(busy: busy, busySceneId: () => sceneId));
  }

  Future<void> _discardLocalDraft() async {
    _draftTimer?.cancel();
    _pendingDraft = null;
    await _repo.clearLocalDraft(arg);
  }

  void _applyServerChat(Chat chat) {
    ref.read(chatControllerProvider(arg).notifier).setChat(chat);
    if (chat.script != null) {
      state = AsyncData(_fromScript(chat.id, chat.script!));
    }
  }

  Future<Chat> _saveToServer(ScriptEditorState current) async {
    final chat = await _repo.save(arg, current.toScript());
    await _discardLocalDraft();
    return chat;
  }

  /// `PUT /script/{chatId}` (also clears the local draft cache).
  Future<void> saveDraft() async {
    final current = state.valueOrNull;
    if (current == null || current.isBusy) return;
    _setBusy(ScriptBusy.saving);
    try {
      _applyServerChat(await _saveToServer(current));
    } catch (_) {
      _setBusy(ScriptBusy.none);
      rethrow;
    }
  }

  /// Regenerates the whole script (local edits are discarded).
  Future<void> regenerateAll({String? instructions}) async {
    final current = state.valueOrNull;
    if (current == null || current.isBusy) return;
    _setBusy(ScriptBusy.regeneratingAll);
    try {
      final chat = await _repo.regenerate(chatId: arg, instructions: instructions);
      await _discardLocalDraft();
      _applyServerChat(chat);
    } catch (_) {
      _setBusy(ScriptBusy.none);
      rethrow;
    }
  }

  /// Regenerates one scene. Unsaved edits are saved first so the server
  /// regenerates against what the user sees.
  Future<void> regenerateScene(int sceneId, {String? instructions}) async {
    final current = state.valueOrNull;
    if (current == null || current.isBusy) return;
    final index = current.scenes.indexWhere((e) => e.id == sceneId);
    if (index < 0) return;
    _setBusy(ScriptBusy.regeneratingScene, sceneId: sceneId);
    try {
      if (current.dirty) await _saveToServer(current);
      final chat = await _repo.regenerate(
        chatId: arg,
        sceneNumber: index + 1,
        instructions: instructions,
      );
      await _discardLocalDraft();
      _applyServerChat(chat);
    } catch (_) {
      _setBusy(ScriptBusy.none);
      rethrow;
    }
  }

  /// Auto-saves pending edits, then starts `POST /video/generate`.
  Future<GenerationJob> startVideo(Resolution resolution) async {
    final current = state.valueOrNull;
    if (current == null) throw const ScriptMissingException();
    if (current.isBusy) throw const AppException('Please wait for the current action to finish.');
    if (current.scenes.isEmpty) {
      throw const AppException('Add at least one scene before generating a video.');
    }
    _setBusy(ScriptBusy.startingVideo);
    try {
      if (current.dirty) {
        _applyServerChat(await _saveToServer(current));
        _setBusy(ScriptBusy.startingVideo);
      }
      final job = await ref
          .read(generationRepositoryProvider)
          .generate(chatId: arg, resolution: resolution);
      _setBusy(ScriptBusy.none);
      return job;
    } catch (_) {
      _setBusy(ScriptBusy.none);
      rethrow;
    }
  }
}

final scriptEditorProvider = AsyncNotifierProvider.autoDispose
    .family<ScriptEditorController, ScriptEditorState, String>(
  ScriptEditorController.new,
);
