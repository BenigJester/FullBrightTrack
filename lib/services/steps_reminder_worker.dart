import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'app_check_service.dart';
import 'leaderboard_service.dart';

@pragma('vm:entry-point')
void hourlyWorkerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();

    final savedDay = prefs.getString('bg_day') ?? '';
    final steps = savedDay == StepsReminderWorker.todayKey()
        ? prefs.getInt('bg_steps') ?? 0
        : 0;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      await AppCheckService.activate();

      await LeaderboardService.publishCurrentUserSummary(todaySteps: steps);
    } catch (_) {
      // Background leaderboard sync is best-effort.
    }

    return Future.value(true);
  });
}

class StepsReminderWorker {
  static const taskName = 'steps-reminder-sync';

  static String todayKey() {
    final now = DateTime.now();

    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }
}
