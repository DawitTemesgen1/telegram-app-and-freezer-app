import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/chat_prefs_store.dart';
import '../../data/followed_chats_store.dart';
import '../../tdlib/telegram_client.dart';
import 'chat_avatar.dart';

class ChatInfoSheet extends StatelessWidget {
  const ChatInfoSheet({
    super.key,
    required this.chatId,
    this.onExport,
  });

  final int chatId;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final client = context.watch<TelegramClient>();
    final chat = client.chatById(chatId);
    final followed = context.watch<FollowedChatsStore>();
    final prefs = context.watch<ChatPrefsStore>();
    final theme = Theme.of(context);

    if (chat == null) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Chat not found'),
        ),
      );
    }

    final muted = followed.isMuted(chatId);
    final pinned = followed.isPinned(chatId);
    final hidePreview = prefs.hidePreviewFor(chatId);
    final silent = prefs.soundFor(chatId) == 'silent';
    final kindLabel = switch (chat.kind) {
      'channel' => 'Channel',
      'group' => 'Group',
      'private' => 'Private chat',
      _ => 'Chat',
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  ChatAvatar(
                    chat: chat,
                    imagePath: client.chatPhotoPath(chatId),
                    size: 72,
                    showKindBadge: false,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    chat.title,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$kindLabel · ${chat.memberCount > 0 ? '${chat.memberCount} members' : 'Members'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Notifications', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Mute chat'),
              value: muted,
              onChanged: (_) => followed.toggleMuted(chatId),
            ),
            SwitchListTile(
              title: const Text('Hide preview'),
              subtitle: const Text('Show title only in notifications'),
              value: hidePreview,
              onChanged: (v) => prefs.setHidePreview(chatId, v),
            ),
            SwitchListTile(
              title: const Text('Silent notifications'),
              value: silent,
              onChanged: (v) =>
                  prefs.setSound(chatId, v ? 'silent' : 'default'),
            ),
            const Divider(height: 28),
            Text('Chat', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(pinned ? 'Unpin from home' : 'Pin to home'),
              onTap: () => followed.togglePinned(chatId),
            ),
            if (onExport != null)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export chat transcript'),
                onTap: () {
                  Navigator.pop(context);
                  onExport!();
                },
              ),
          ],
        ),
      ),
    );
  }
}
