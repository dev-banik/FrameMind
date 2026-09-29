import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Offline cache backed by Hive. Values are stored as JSON strings so no
/// TypeAdapters / code generation are needed.
class HiveCache {
  static const String historyBox = 'fm_history';
  static const String projectsBox = 'fm_projects';
  static const String draftsBox = 'fm_drafts';
  static const String chatsBox = 'fm_chats';

  static const List<String> _allBoxes = [historyBox, projectsBox, draftsBox, chatsBox];

  static bool _initialized = false;

  static Future<void> init() async {
    if (!_initialized) {
      await Hive.initFlutter('framemind');
      _initialized = true;
    }
    for (final name in _allBoxes) {
      if (!Hive.isBoxOpen(name)) {
        try {
          await Hive.openBox<String>(name);
        } catch (e) {
          // A corrupt cache must never block app start: wipe and reopen.
          debugPrint('HiveCache: reopening corrupt box $name: $e');
          await Hive.deleteBoxFromDisk(name);
          await Hive.openBox<String>(name);
        }
      }
    }
  }

  Box<String>? _box(String name) =>
      Hive.isBoxOpen(name) ? Hive.box<String>(name) : null;

  Future<void> putJson(String boxName, String key, Object? json) async {
    final box = _box(boxName);
    if (box == null) return;
    try {
      await box.put(key, jsonEncode(json));
    } catch (e) {
      debugPrint('HiveCache: failed to write $boxName/$key: $e');
    }
  }

  Object? getJson(String boxName, String key) {
    final raw = _box(boxName)?.get(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String boxName, String key) async {
    await _box(boxName)?.delete(key);
  }

  /// Clears every cache box (used on sign-out so accounts never mix).
  Future<void> clearAll() async {
    for (final name in _allBoxes) {
      await _box(name)?.clear();
    }
  }
}

final hiveCacheProvider = Provider<HiveCache>((ref) => HiveCache());
