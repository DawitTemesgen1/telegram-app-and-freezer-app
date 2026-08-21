import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationTapCallback = void Function(int chatId);
typedef NotificationReplyCallback = void Function(int chatId, String reply);

class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'tg_focus_messages';
  static const _channelName = 'Followed group messages';
  static const _replyActionId = 'reply_action';

  NotificationTapCallback? onTap;
  NotificationReplyCallback? onReply;
  int _badgeCount = 0;

  int get badgeCount => _badgeCount;

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');
    const initSettings = InitializationSettings(
      android: android,
      linux: linux,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        if (response.actionId == _replyActionId) {
          final reply = response.input?.trim();
          if (reply != null && reply.isNotEmpty) {
            final chatId = int.tryParse(payload);
            if (chatId != null) onReply?.call(chatId, reply);
          }
          return;
        }
        final chatId = int.tryParse(payload);
        if (chatId != null) onTap?.call(chatId);
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'New messages in groups you follow',
          importance: Importance.high,
        ),
      );
    }
  }

  void setBadgeCount(int count) {
    _badgeCount = count;
  }

  Future<void> showMessage({
    required int chatId,
    required String title,
    required String body,
    bool hidePreview = false,
    bool silent = false,
  }) async {
    final displayBody = hidePreview ? 'New message' : body;
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'New messages in groups you follow',
      importance: silent ? Importance.low : Importance.high,
      priority: silent ? Priority.low : Priority.high,
      playSound: !silent,
      enableVibration: !silent,
      groupKey: 'tg_focus_chat_$chatId',
      setAsGroupSummary: false,
      styleInformation: BigTextStyleInformation(displayBody),
      actions: Platform.isAndroid
          ? [
              const AndroidNotificationAction(
                _replyActionId,
                'Reply',
                inputs: [
                  AndroidNotificationActionInput(
                    label: 'Message',
                  ),
                ],
              ),
            ]
          : null,
    );

    final details = NotificationDetails(
      android: androidDetails,
      linux: LinuxNotificationDetails(
        defaultActionName: 'Open',
        urgency: silent
            ? LinuxNotificationUrgency.low
            : LinuxNotificationUrgency.normal,
      ),
    );

    await _plugin.show(
      id: chatId.hashCode & 0x7fffffff,
      title: title,
      body: displayBody,
      notificationDetails: details,
      payload: chatId.toString(),
    );
  }
}
