import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'hourly_worker.dart';

class ReminderSchedulerService {
  const ReminderSchedulerService._();

  static const enabledKey = 'hourly_step_reminders_enabled';
  static const intervalKey = 'step_reminder_interval_hours';
  static const taskUniqueName = 'hourly-reminder';
  static const _nativeChannel = MethodChannel('fullbright_track/step_service');

  static Future<void> scheduleFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    await schedule(
      enabled: prefs.getBool(enabledKey) ?? true,
      intervalHours: prefs.getInt(intervalKey) ?? 2,
    );
  }

  static Future<void> schedule({
    required bool enabled,
    required int intervalHours,
  }) async {
    final safeInterval = _normalizeInterval(intervalHours);

    await Workmanager().cancelByUniqueName(taskUniqueName);

    if (!enabled) {
      await _cancelNativeReminders();
      return;
    }

    await _scheduleNativeReminders();
    await Workmanager().registerPeriodicTask(
      taskUniqueName,
      HourlyWorker.taskName,
      frequency: Duration(hours: safeInterval),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  static int _normalizeInterval(int intervalHours) {
    if (intervalHours == 1 || intervalHours == 2 || intervalHours == 3) {
      return intervalHours;
    }

    return 2;
  }

  static Future<void> _scheduleNativeReminders() async {
    try {
      await _nativeChannel.invokeMethod<void>('scheduleReminders');
    } on MissingPluginException {
      // Native reminder alarms are Android-only.
    }
  }

  static Future<void> _cancelNativeReminders() async {
    try {
      await _nativeChannel.invokeMethod<void>('cancelReminders');
    } on MissingPluginException {
      // Native reminder alarms are Android-only.
    }
  }
}
