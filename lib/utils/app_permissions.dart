import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Request runtime permissions needed by TG Focus on Android.
Future<void> requestAppPermissions() async {
  if (!Platform.isAndroid) return;

  final permissions = <Permission>[
    Permission.notification,
    Permission.microphone,
    Permission.photos,
    Permission.videos,
    Permission.audio,
    Permission.storage,
  ];

  await permissions.request();
}
