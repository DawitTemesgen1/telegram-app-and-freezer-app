import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_settings.dart';
import 'data/chat_prefs_store.dart';
import 'data/drafts_store.dart';
import 'data/followed_chats_store.dart';
import 'data/send_queue_store.dart';
import 'notify/notification_service.dart';
import 'tdlib/telegram_client.dart';
import 'utils/app_permissions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await requestAppPermissions();

  final settings = AppSettings();
  await settings.load();

  final followed = FollowedChatsStore();
  await followed.load();

  final drafts = DraftsStore();
  await drafts.load();

  final chatPrefs = ChatPrefsStore();
  await chatPrefs.load();

  final sendQueue = SendQueueStore();
  await sendQueue.load();

  final notifications = NotificationService();
  await notifications.init();

  final client = TelegramClient();
  client.attachSendQueue(sendQueue);
  client.attachChatPrefs(chatPrefs);
  await client.start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: client),
        ChangeNotifierProvider.value(value: followed),
        ChangeNotifierProvider.value(value: drafts),
        ChangeNotifierProvider.value(value: chatPrefs),
        ChangeNotifierProvider.value(value: sendQueue),
        Provider.value(value: notifications),
      ],
      child: const TgFocusApp(),
    ),
  );
}
