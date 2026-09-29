import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../projects/providers/projects_providers.dart';
import '../../settings/providers/settings_providers.dart';
import 'history_providers.dart';

/// Invalidates every provider that lists chats (history, recent chats,
/// projects and their chat counts). Pass `ref.invalidate` from either a
/// `Ref` or a `WidgetRef`.
void refreshChatLists(void Function(ProviderOrFamily provider) invalidate) {
  invalidate(historyControllerProvider);
  invalidate(recentChatsProvider);
  invalidate(projectsControllerProvider);
  invalidate(projectDetailProvider);
}

/// Also refreshes the quota shown on Home / Profile.
void refreshChatListsAndQuota(void Function(ProviderOrFamily provider) invalidate) {
  refreshChatLists(invalidate);
  invalidate(userProfileProvider);
}
