import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/foreground_callback.dart';

class StepForegroundService {
  static Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      notificationTitle: 'Step Tracker Active',
      notificationText: 'Tracking steps...',
      callback: startCallback,
      notificationIcon: const NotificationIcon(metaDataName: 'ic_launcher'),
    );
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}
