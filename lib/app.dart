import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'data/app_settings.dart';
import 'data/chat_prefs_store.dart';
import 'data/followed_chats_store.dart';
import 'data/send_queue_store.dart';
import 'notify/notification_service.dart';
import 'tdlib/telegram_client.dart';
import 'theme/app_theme.dart';
import 'ui/chat/chat_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/login/login_screen.dart';
import 'ui/picker/group_picker_screen.dart';
import 'ui/widgets/connection_banner.dart';

class TgFocusApp extends StatefulWidget {
  const TgFocusApp({super.key});

  @override
  State<TgFocusApp> createState() => _TgFocusAppState();
}

class _TgFocusAppState extends State<TgFocusApp> {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = context.read<TelegramClient>();
      final store = context.read<FollowedChatsStore>();
      final chatPrefs = context.read<ChatPrefsStore>();
      final notifications = context.read<NotificationService>();

      notifications.onTap = (chatId) {
        _navKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
        );
      };

      notifications.onReply = (chatId, reply) async {
        await client.sendText(chatId, reply);
        _navKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
        );
      };

      client.onNewIncomingMessage = (chat, message) {
        if (!store.isFollowed(chat.id)) return;
        if (store.isMuted(chat.id)) return;
        if (chatPrefs.mentionsOnly &&
            !message.mentionsMe &&
            !message.containsUnreadMention) {
          return;
        }
        final hidePreview = chatPrefs.hidePreviewFor(chat.id);
        final silent = chatPrefs.soundFor(chat.id) == 'silent';
        notifications.showMessage(
          chatId: chat.id,
          title: chat.title,
          body: message.text,
          hidePreview: hidePreview,
          silent: silent,
        );
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final store = context.watch<FollowedChatsStore>();
    final client = context.watch<TelegramClient>();
    final notifications = context.read<NotificationService>();

    final chats = client.followedChats(store.ids, pinnedIds: store.pinnedIds);
    final totalUnread =
        chats.fold<int>(0, (sum, chat) => sum + chat.unreadCount);
    notifications.setBadgeCount(totalUnread);
    final title = totalUnread > 0 ? 'TG Focus ($totalUnread)' : 'TG Focus';

    return MaterialApp(
      navigatorKey: _navKey,
      title: title,
      theme: AppTheme.light(accent: settings.accentColor),
      darkTheme: AppTheme.dark(accent: settings.accentColor),
      themeMode: settings.materialThemeMode,
      home: const _RootGate(),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final client = context.watch<TelegramClient>();
    final store = context.watch<FollowedChatsStore>();
    final chatPrefs = context.watch<ChatPrefsStore>();
    final sendQueue = context.watch<SendQueueStore>();

    if (!AppConfig.hasCredentials && client.lastError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(client.lastError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (!client.isReady) {
      return const LoginScreen();
    }

    if (!store.isLoaded || !chatPrefs.isLoaded || !sendQueue.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!store.pickerCompleted) {
      return const GroupPickerScreen();
    }

    return Column(
      children: [
        ConnectionBanner(state: client.connectionState),
        const Expanded(child: HomeScreen()),
      ],
    );
  }
}
