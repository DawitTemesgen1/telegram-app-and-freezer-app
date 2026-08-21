import 'package:flutter/material.dart';

import '../../tdlib/focus_chat.dart';
import '../../utils/message_utils.dart';
import 'chat_avatar.dart';

/// Home list row for a followed group or channel.
class ChatCard extends StatelessWidget {
  const ChatCard({
    super.key,
    required this.chat,
    required this.unread,
    required this.muted,
    required this.pinned,
    required this.onTap,
    required this.onLongPress,
    required this.onTogglePin,
    this.photoPath,
  });

  final FocusChat chat;
  final int unread;
  final bool muted;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onTogglePin;
  final String? photoPath;

  bool get _isChannel => chat.kind == 'channel';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = unread > 0;
    final accent = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                if (hasUnread)
                  accent.withValues(alpha: 0.14)
                else if (pinned)
                  accent.withValues(alpha: 0.06)
                else
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: pinned ? 0.85 : 0.45,
                ),
              ],
            ),
            border: Border.all(
              color: hasUnread
                  ? accent.withValues(alpha: 0.35)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ChatAvatar(
                  chat: chat,
                  imagePath: photoPath,
                  highlighted: hasUnread,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (pinned) ...[
                            Icon(Icons.push_pin_rounded, size: 13, color: accent),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight:
                                    hasUnread ? FontWeight.w700 : FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            chat.lastMessageDate > 0
                                ? formatMessageTime(chat.lastMessageDate)
                                : '',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: hasUnread
                                  ? accent
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(
                                alpha: 0.45,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isChannel ? 'Channel' : 'Group',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          if (muted) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              chat.lastPreview.isEmpty
                                  ? 'No messages yet'
                                  : chat.lastPreview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: hasUnread
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight:
                                    hasUnread ? FontWeight.w600 : FontWeight.w400,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: 8),
                            Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: muted
                                    ? theme.colorScheme.outlineVariant
                                    : accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ] else
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: pinned ? 'Unpin' : 'Pin',
                              onPressed: onTogglePin,
                              icon: Icon(
                                pinned
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
