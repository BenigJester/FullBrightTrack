import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'leaderboard_service.dart';
import 'notification_service.dart';

class HourlyWorker {
  static const taskName = 'hourly-step-reminder';

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      final prefs = await SharedPreferences.getInstance();

      final savedDay = prefs.getString('bg_day') ?? '';
      final steps = savedDay == _todayKey() ? prefs.getInt('bg_steps') ?? 0 : 0;

      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }

        await LeaderboardService.publishCurrentUserSummary(todaySteps: steps);
      } catch (_) {
        // Background leaderboard sync is best-effort.
      }

      final enabled = prefs.getBool('hourly_step_reminders_enabled') ?? true;
      if (!enabled) {
        return Future.value(true);
      }

      await NotificationService.initialize();

      await NotificationService.showHourlySteps(steps);

      return Future.value(true);
    });
  }

  static String _todayKey() {
    final now = DateTime.now();

    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }
}
