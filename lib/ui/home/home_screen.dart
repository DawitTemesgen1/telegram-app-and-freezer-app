import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/chat_prefs_store.dart';
import '../../data/followed_chats_store.dart';
import '../../tdlib/telegram_client.dart';
import '../../utils/app_snack.dart';
import '../chat/chat_screen.dart';
import '../picker/group_picker_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/chat_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _unreadOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyK) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _query.isNotEmpty) {
      _searchController.clear();
      setState(() => _query = '');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<TelegramClient>();
    final store = context.watch<FollowedChatsStore>();
    final chatPrefs = context.watch<ChatPrefsStore>();
    final chats = client.followedChats(
      store.ids,
      pinnedIds: store.pinnedIds,
    );
    final q = _query.trim().toLowerCase();
    var filtered = q.isEmpty
        ? chats
        : chats.where((chat) {
            final title = chat.title.toLowerCase();
            final preview = chat.lastPreview.toLowerCase();
            return title.contains(q) || preview.contains(q);
          }).toList();

    if (_unreadOnly) {
      filtered = filtered.where((chat) {
        final local = chatPrefs.isLocallyMarkedUnread(chat.id);
        return chat.unreadCount > 0 ||
            chat.isMarkedAsUnread ||
            local;
      }).toList();
    }

    final theme = Theme.of(context);
    final totalUnread = chats.fold<int>(0, (sum, chat) {
      if (chatPrefs.isLocallyMarkedUnread(chat.id) && chat.unreadCount == 0) {
        return sum + 1;
      }
      return sum + chat.unreadCount;
    });

    return Focus(
      onKeyEvent: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TG Focus'),
          actions: [
            if (totalUnread > 0)
              IconButton(
                tooltip: 'Mark all read',
                onPressed: () async {
                  await client.markAllFollowedRead(store.ids);
                  for (final id in store.ids) {
                    await chatPrefs.setLocallyMarkedUnread(id, false);
                  }
                  if (context.mounted) {
                    showAppSnack(context, 'Marked all as read');
                  }
                },
                icon: const Icon(Icons.done_all),
              ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: SearchBar(
                focusNode: _searchFocus,
                controller: _searchController,
                hintText: 'Search chats (Ctrl+K)',
                leading: const Icon(Icons.search),
                trailing: [
                  IconButton(
                    tooltip: _unreadOnly ? 'Show all chats' : 'Unread only',
                    isSelected: _unreadOnly,
                    onPressed: () =>
                        setState(() => _unreadOnly = !_unreadOnly),
                    icon: Icon(
                      _unreadOnly
                          ? Icons.mark_email_unread
                          : Icons.mark_email_unread_outlined,
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
                ],
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              q.isEmpty && !_unreadOnly
                                  ? 'No followed groups yet'
                                  : 'No chats match your filters',
                              style: theme.textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            if (q.isEmpty && !_unreadOnly) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Pick the ones you do not want to miss.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const GroupPickerScreen(
                                        allowSkip: true,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Choose groups'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => client.loadChats(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final chat = filtered[index];
                          final localUnread =
                              chatPrefs.isLocallyMarkedUnread(chat.id);
                          final unread = chat.unreadCount > 0
                              ? chat.unreadCount
                              : (localUnread || chat.isMarkedAsUnread ? 1 : 0);
                          final muted = store.isMuted(chat.id);
                          final pinned = store.isPinned(chat.id);

                          return TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: Duration(
                              milliseconds: 220 + (index * 28).clamp(0, 180),
                            ),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 10 * (1 - value)),
                                  child: child,
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ChatCard(
                                chat: chat,
                                unread: unread,
                                muted: muted,
                                pinned: pinned,
                                photoPath: client.chatPhotoPath(chat.id),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ChatScreen(chatId: chat.id),
                                    ),
                                  );
                                },
                                onTogglePin: () => store.togglePinned(chat.id),
                                onLongPress: () {
                                  final hidePreview =
                                      chatPrefs.hidePreviewFor(chat.id);
                                  final silent =
                                      chatPrefs.soundFor(chat.id) == 'silent';
                                  showModalBottomSheet<void>(
                                    context: context,
                                    showDragHandle: true,
                                    builder: (context) {
                                      return SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              leading: const Icon(
                                                Icons.mark_email_unread_outlined,
                                              ),
                                              title: const Text(
                                                'Mark as unread',
                                              ),
                                              onTap: () async {
                                                await client.toggleChatMarkedUnread(
                                                  chat.id,
                                                  marked: true,
                                                );
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                            ),
                                            ListTile(
                                              leading: Icon(
                                                pinned
                                                    ? Icons.push_pin_rounded
                                                    : Icons.push_pin_outlined,
                                              ),
                                              title: Text(
                                                pinned ? 'Unpin' : 'Pin to top',
                                              ),
                                              onTap: () {
                                                store.togglePinned(chat.id);
                                                Navigator.pop(context);
                                              },
                                            ),
                                            ListTile(
                                              leading: Icon(
                                                muted
                                                    ? Icons
                                                        .notifications_active_outlined
                                                    : Icons
                                                        .notifications_off_outlined,
                                              ),
                                              title:
                                                  Text(muted ? 'Unmute' : 'Mute'),
                                              onTap: () {
                                                store.toggleMuted(chat.id);
                                                Navigator.pop(context);
                                              },
                                            ),
                                            ListTile(
                                              leading: Icon(
                                                hidePreview
                                                    ? Icons.visibility_outlined
                                                    : Icons
                                                        .visibility_off_outlined,
                                              ),
                                              title: Text(
                                                hidePreview
                                                    ? 'Show notification preview'
                                                    : 'Hide notification preview',
                                              ),
                                              onTap: () {
                                                chatPrefs.setHidePreview(
                                                  chat.id,
                                                  !hidePreview,
                                                );
                                                Navigator.pop(context);
                                              },
                                            ),
                                            ListTile(
                                              leading: Icon(
                                                silent
                                                    ? Icons.volume_up_outlined
                                                    : Icons.volume_off_outlined,
                                              ),
                                              title: Text(
                                                silent
                                                    ? 'Default notification sound'
                                                    : 'Silent notifications',
                                              ),
                                              onTap: () {
                                                chatPrefs.setSound(
                                                  chat.id,
                                                  silent ? 'default' : 'silent',
                                                );
                                                Navigator.pop(context);
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
