/// Timers are scheduled natively via AlarmManager from FreezeService.
/// This class remains as a thin init hook for app startup reconcile.
class TimerService {
  static Future<void> initialize() async {
    // Native alarms + BootReceiver handle unfreeze.
  }
}
