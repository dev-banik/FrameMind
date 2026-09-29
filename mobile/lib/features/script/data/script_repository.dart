import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/hive_cache.dart';
import '../../../core/utils/json.dart';
import '../../history/data/models/chat_models.dart';
import 'models/script.dart';

/// Locally cached, possibly unsaved script edits.
class LocalDraft {
  const LocalDraft({required this.script, required this.savedAt});

  final Script script;
  final DateTime savedAt;
}

/// `/script/*` endpoints + local (Hive) draft storage.
class ScriptRepository {
  ScriptRepository(this._api, this._cache);

  final ApiClient _api;
  final HiveCache _cache;

  /// `POST /script/generate`
  Future<Chat> generate({
    required String chatId,
    required Language language,
    required int durationSeconds,
    required VideoStyle style,
    required VoiceType voiceType,
    String? userPrompt,
  }) async {
    final prompt = userPrompt?.trim();
    final data = await _api.post(
      '/script/generate',
      data: {
        'chatId': chatId,
        'language': language.apiValue,
        'durationSeconds': durationSeconds,
        'style': style.apiValue,
        'voiceType': voiceType.apiValue,
        if (prompt != null && prompt.isNotEmpty) 'userPrompt': prompt,
      },
      receiveTimeout: AppConfig.scriptTimeout,
    );
    return Chat.fromJson(asJsonMap(data));
  }

  /// `POST /script/regenerate` - omit [sceneNumber] to regenerate everything.
  Future<Chat> regenerate({
    required String chatId,
    int? sceneNumber,
    String? instructions,
  }) async {
    final text = instructions?.trim();
    final data = await _api.post(
      '/script/regenerate',
      data: {
        'chatId': chatId,
        if (sceneNumber != null) 'sceneNumber': sceneNumber,
        if (text != null && text.isNotEmpty) 'instructions': text,
      },
      receiveTimeout: AppConfig.scriptTimeout,
    );
    return Chat.fromJson(asJsonMap(data));
  }

  /// `PUT /script/{chatId}` - scenes are renumbered server-side.
  Future<Chat> save(String chatId, Script script) async {
    final data = await _api.put(
      '/script/$chatId',
      data: {'script': script.toJson()},
    );
    return Chat.fromJson(asJsonMap(data));
  }

  // ---- Local drafts -------------------------------------------------------

  Future<void> saveLocalDraft(String chatId, Script script) {
    return _cache.putJson(HiveCache.draftsBox, chatId, {
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'script': script.toJson(),
    });
  }

  LocalDraft? loadLocalDraft(String chatId) {
    final json = asJsonMapOrNull(_cache.getJson(HiveCache.draftsBox, chatId));
    if (json == null) return null;
    final savedAt = asDateOrNull(json['savedAt']);
    final scriptJson = asJsonMapOrNull(json['script']);
    if (savedAt == null || scriptJson == null) return null;
    return LocalDraft(script: Script.fromJson(scriptJson), savedAt: savedAt);
  }

  Future<void> clearLocalDraft(String chatId) =>
      _cache.remove(HiveCache.draftsBox, chatId);
}

final scriptRepositoryProvider = Provider<ScriptRepository>(
  (ref) => ScriptRepository(
    ref.watch(apiClientProvider),
    ref.watch(hiveCacheProvider),
  ),
);
