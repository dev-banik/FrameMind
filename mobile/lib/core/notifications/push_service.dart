import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/history/providers/chat_list_refresh.dart';
import '../../features/history/providers/history_providers.dart';
import '../../features/settings/data/user_repository.dart';
import '../storage/secure_store.dart';
import '../utils/snackbar.dart';

/// A chat the user asked to open from a notification. The app shell consumes
/// it once navigation is ready.
class PendingChatLink extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String chatId) => state = chatId;

  String? consume() {
    final value = state;
    state = null;
    return value;
  }
}

final pendingChatLinkProvider =
    NotifierProvider<PendingChatLink, String?>(PendingChatLink.new);

/// Firebase Cloud Messaging integration:
/// * asks for permission and registers the device token with the API after
///   sign-in and whenever it rotates;
/// * shows foreground messages as snackbars;
/// * routes notification taps (`data.type` = video_ready | video_failed,
///   `data.chatId`) to the chat.
class PushService {
  PushService(this._ref);

  final Ref _ref;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  String? _activeUid;

  Future<void> onSignedIn(User user) async {
    if (_activeUid == user.uid) return;
    await _cancelSubscriptions();
    _activeUid = user.uid;

    try {
      final messaging = FirebaseMessaging.instance;

      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
      _messageSub = FirebaseMessaging.onMessage.listen(_handleForeground);

      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('PushService: notification permission denied');
        return;
      }

      final token = await _getToken(messaging);
      if (token != null) await _register(token);
      _tokenSub = messaging.onTokenRefresh.listen(_register);
    } catch (e) {
      debugPrint('PushService: setup failed: $e');
    }
  }

  Future<void> onSignedOut() async {
    final uid = _activeUid;
    _activeUid = null;
    await _cancelSubscriptions();
    if (uid != null) {
      await _ref.read(secureStoreProvider).clearRegisteredDeviceToken(uid);
    }
    try {
      // Stop delivering this account's notifications to this device.
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('PushService: deleteToken failed: $e');
    }
  }

  Future<String?> _getToken(FirebaseMessaging messaging) async {
    if (!kIsWeb && Platform.isIOS) {
      // The FCM token is only available once APNs has issued a device token.
      for (var attempt = 0; attempt < 5; attempt++) {
        final apns = await messaging.getAPNSToken();
        if (apns != null) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    try {
      return await messaging.getToken();
    } catch (e) {
      debugPrint('PushService: getToken failed: $e');
      return null;
    }
  }

  Future<void> _register(String token) async {
    final uid = _activeUid;
    if (uid == null) return;
    final store = _ref.read(secureStoreProvider);
    try {
      final platform = (!kIsWeb && Platform.isIOS) ? 'ios' : 'android';
      await _ref.read(userRepositoryProvider).registerDeviceToken(token, platform);
      await store.setRegisteredDeviceToken(uid, token);
    } catch (e) {
      debugPrint('PushService: device token registration failed: $e');
    }
  }

  String? _chatIdOf(RemoteMessage message) {
    final chatId = message.data['chatId'];
    return chatId is String && chatId.isNotEmpty ? chatId : null;
  }

  void _handleTap(RemoteMessage message) {
    final chatId = _chatIdOf(message);
    if (chatId == null) return;
    _ref.invalidate(chatControllerProvider(chatId));
    refreshChatListsAndQuota(_ref.invalidate);
    _ref.read(pendingChatLinkProvider.notifier).set(chatId);
  }

  void _handleForeground(RemoteMessage message) {
    final type = message.data['type'];
    final chatId = _chatIdOf(message);
    if (chatId != null) {
      _ref.invalidate(chatControllerProvider(chatId));
    }
    refreshChatListsAndQuota(_ref.invalidate);

    void open() {
      if (chatId != null) _ref.read(pendingChatLinkProvider.notifier).set(chatId);
    }

    switch (type) {
      case 'video_ready':
        showAppSnackBar(
          message.notification?.body ?? 'Your video is ready!',
          actionLabel: chatId != null ? 'View' : null,
          onAction: open,
          duration: const Duration(seconds: 6),
        );
      case 'video_failed':
        showAppSnackBar(
          message.notification?.body ?? 'Video generation failed.',
          isError: true,
          actionLabel: chatId != null ? 'Open' : null,
          onAction: open,
          duration: const Duration(seconds: 6),
        );
      default:
        final title = message.notification?.title;
        final body = message.notification?.body;
        if (title != null || body != null) {
          showAppSnackBar([title, body].whereType<String>().join(' - '));
        }
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    await _openedSub?.cancel();
    _tokenSub = null;
    _messageSub = null;
    _openedSub = null;
  }

  void dispose() {
    _cancelSubscriptions();
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref);
  ref.onDispose(service.dispose);
  return service;
});
