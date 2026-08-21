import 'package:shared_preferences/shared_preferences.dart';
import '../models/frozen_app.dart';
import 'freeze_service.dart';

class FrozenAppsManager {
  static const String _key = 'frozen_apps';

  static Future<List<FrozenApp>> getFrozenApps() async {
    await FreezeService.reconcileExpired();
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_key) ?? [];
    final apps = list.map((e) => FrozenApp.fromJson(e)).toList();
    final now = DateTime.now();
    final stillFrozen = <FrozenApp>[];
    final expired = <String>[];
    for (final app in apps) {
      final indefinite =
          app.unfreezeTime.isAfter(now.add(const Duration(days: 365 * 40)));
      if (!indefinite && app.unfreezeTime.isBefore(now)) {
        expired.add(app.packageName);
      } else {
        stillFrozen.add(app);
      }
    }
    if (expired.isNotEmpty) {
      try {
        await FreezeService.unfreezeApps(expired);
      } catch (_) {}
      await saveFrozenApps(stillFrozen);
    }
    return stillFrozen;
  }

  static Future<void> saveFrozenApps(List<FrozenApp> apps) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = apps.map((e) => e.toJson()).toList();
    await prefs.setStringList(_key, list);
  }

  static Future<void> freezeApp(
    String packageName,
    String appName,
    Duration duration,
  ) async {
    final owner = await FreezeService.isDeviceOwner();
    if (!owner) {
      throw Exception('NOT_DEVICE_OWNER');
    }

    final apps = await getFrozenApps();
    final unfreezeTime = DateTime.now().add(duration);

    final existingIndex = apps.indexWhere((a) => a.packageName == packageName);
    if (existingIndex >= 0) {
      apps[existingIndex] = FrozenApp(
        packageName: packageName,
        appName: appName,
        unfreezeTime: unfreezeTime,
      );
    } else {
      apps.add(
        FrozenApp(
          packageName: packageName,
          appName: appName,
          unfreezeTime: unfreezeTime,
        ),
      );
    }

    await FreezeService.freezeApps([packageName], unfreezeTime);
    await saveFrozenApps(apps);
  }

  static Future<void> unfreezeApp(String packageName) async {
    final apps = await getFrozenApps();
    apps.removeWhere((a) => a.packageName == packageName);
    await saveFrozenApps(apps);
    await FreezeService.unfreezeApps([packageName]);
  }
}
