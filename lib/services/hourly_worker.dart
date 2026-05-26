import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'notification_service.dart';

class HourlyWorker {
  static const taskName = 'hourly-step-reminder';

  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      final prefs = await SharedPreferences.getInstance();

      final enabled = prefs.getBool('hourly_step_reminders_enabled') ?? true;
      if (!enabled) {
        return Future.value(true);
      }

      final steps = prefs.getInt('bg_steps') ?? 0;

      await NotificationService.initialize();

      await NotificationService.showHourlySteps(steps);

      return Future.value(true);
    });
  }
}
