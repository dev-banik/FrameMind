import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/network_thumbnail.dart';
import '../../data/models/chat_models.dart';

/// History-style row: thumbnail, title, duration, language, date, status.
class ChatListTile extends StatelessWidget {
  const ChatListTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.trailing,
    this.showTime = false,
  });

  final ChatSummary chat;
  final VoidCallback onTap;
  final Widget? trailing;

  /// Show time-of-day instead of date (e.g. inside a "Today" section).
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = <String>[
      if (chat.durationSeconds != null) formatDurationShort(chat.durationSeconds),
      if (chat.language != null) chat.language!.apiValue,
      if (chat.createdAt != null)
        showTime ? formatTime(chat.createdAt) : formatDate(chat.createdAt),
    ];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Stack(
              children: [
                NetworkThumbnail(url: chat.thumbnailUrl, width: 76, height: 56, borderRadius: 10),
                if (chat.hasVideo)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(status: chat.status),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
