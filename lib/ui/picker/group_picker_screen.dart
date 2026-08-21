import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/followed_chats_store.dart';
import '../../tdlib/telegram_client.dart';
import '../widgets/chat_avatar.dart';

class GroupPickerScreen extends StatefulWidget {
  const GroupPickerScreen({super.key, this.allowSkip = false});

  final bool allowSkip;

  @override
  State<GroupPickerScreen> createState() => _GroupPickerScreenState();
}

class _GroupPickerScreenState extends State<GroupPickerScreen> {
  late Set<int> _selected;
  late Set<int> _muted;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final store = context.read<FollowedChatsStore>();
    _selected = Set<int>.from(store.ids);
    _muted = Set<int>.from(store.mutedIds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = context.read<TelegramClient>();
      if (client.allGroupChats.isEmpty) {
        client.loadChats();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<TelegramClient>();
    final theme = Theme.of(context);
    final groups = client.allGroupChats.where((chat) {
      if (_query.isEmpty) return true;
      return chat.title.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose groups'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: client.isLoadingChats ? null : () => client.loadChats(),
            icon: const Icon(Icons.refresh),
          ),
          if (widget.allowSkip)
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Cancel'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search groups',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Select groups to follow. Mute keeps them visible without alerts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (client.isLoadingChats) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => client.loadChats(),
              child: groups.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.4,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                client.isLoadingChats
                                    ? 'Loading your groups…'
                                    : 'No groups found yet.\nPull down or tap refresh.\n(Known chats: ${client.knownChatCount})',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final chat = groups[index];
                        final checked = _selected.contains(chat.id);
                        final muted = _muted.contains(chat.id);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: checked
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.08)
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                setState(() {
                                  if (checked) {
                                    _selected.remove(chat.id);
                                    _muted.remove(chat.id);
                                  } else {
                                    _selected.add(chat.id);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: checked,
                                      onChanged: (value) {
                                        setState(() {
                                          if (value == true) {
                                            _selected.add(chat.id);
                                          } else {
                                            _selected.remove(chat.id);
                                            _muted.remove(chat.id);
                                          }
                                        });
                                      },
                                    ),
                                    ChatAvatar(
                                      chat: chat,
                                      imagePath: client.chatPhotoPath(chat.id),
                                      size: 36,
                                      showKindBadge: false,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            chat.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            chat.lastPreview,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (checked)
                                      IconButton(
                                        tooltip: muted ? 'Unmute' : 'Mute',
                                        onPressed: () {
                                          setState(() {
                                            if (muted) {
                                              _muted.remove(chat.id);
                                            } else {
                                              _muted.add(chat.id);
                                            }
                                          });
                                        },
                                        icon: Icon(
                                          muted
                                              ? Icons.notifications_off
                                              : Icons.notifications_none,
                                          color: muted
                                              ? theme.colorScheme.primary
                                              : theme
                                                  .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () async {
                  final store = context.read<FollowedChatsStore>();
                  await store.replaceAll(
                    _selected,
                    mutedIds: _muted.intersection(_selected),
                  );
                  if (context.mounted) {
                    if (widget.allowSkip) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                child: Text(
                  _selected.isEmpty
                      ? 'Continue without groups'
                      : 'Follow ${_selected.length} group${_selected.length == 1 ? '' : 's'}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
