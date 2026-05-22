import 'package:flutter/cupertino.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class StepBackgroundHandler extends TaskHandler {
  int _lastNotificationSteps = -1;
  String _currentDay = "";

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Step Tracker Active',
      notificationText: 'Tracking daily activity',
    );

    debugPrint("Foreground service started");
  }

  // ================= LIVE DATA FROM StepsService =================
  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;

    final steps = data['steps'];
    final day = data['day'];

    if (steps is! int) return;
    if (day is! String) return;

    _updateNotification(steps, day);
  }

  // ================= UPDATE NOTIFICATION =================
  Future<void> _updateNotification(int steps, String day) async {
    // reset counter if new day
    if (_currentDay != day) {
      _currentDay = day;
      _lastNotificationSteps = -1;
    }

    // avoid unnecessary UI updates
    if (steps == _lastNotificationSteps) return;

    _lastNotificationSteps = steps;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Step Tracker Active',
      notificationText: '$steps steps today',
    );
  }

  // ================= FALLBACK (optional periodic refresh) =================
  @override
  void onRepeatEvent(DateTime timestamp) {
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isStopped) async {
    debugPrint("Foreground service destroyed");
  }
}
