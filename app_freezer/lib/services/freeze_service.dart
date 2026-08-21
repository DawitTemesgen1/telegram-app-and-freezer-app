import 'package:flutter/services.dart';

class FreezeService {
  static const MethodChannel _channel =
      MethodChannel('com.example.app_freezer/freeze');

  static Future<bool> isDeviceOwner() async {
    try {
      final v = await _channel.invokeMethod<bool>('isDeviceOwner');
      return v ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String> getSetupAdbCommand() async {
    try {
      final v = await _channel.invokeMethod<String>('getSetupAdbCommand');
      return v ??
          'adb shell dpm set-device-owner com.example.app_freezer/.DeviceAdminReceiver';
    } on PlatformException {
      return 'adb shell dpm set-device-owner com.example.app_freezer/.DeviceAdminReceiver';
    }
  }

  static Future<List<Map<String, dynamic>>> getInstalledApps({
    bool includeSystemApps = false,
  }) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getInstalledApps',
        {'includeSystemApps': includeSystemApps},
      );
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException {
      return [];
    }
  }

  static Future<void> freezeApps(
    List<String> packages,
    DateTime unfreezeTime,
  ) async {
    await _channel.invokeMethod('suspendPackages', {
      'packages': packages,
      'unfreezeAtEpochMs': unfreezeTime.millisecondsSinceEpoch,
    });
  }

  static Future<void> unfreezeApps(List<String> packages) async {
    await _channel.invokeMethod('unsuspendPackages', {
      'packages': packages,
    });
  }

  static Future<void> reconcileExpired() async {
    try {
      await _channel.invokeMethod('reconcileExpired');
    } on PlatformException {
      // ignore
    }
  }
}
