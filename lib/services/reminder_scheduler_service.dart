import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'steps_reminder_worker.dart';

class ReminderSchedulerService {
  const ReminderSchedulerService._();

  static const enabledKey = 'hourly_step_reminders_enabled';
  static const minStepsKey = 'step_reminder_min_steps';
  static const taskUniqueName = 'steps-reminder';
  static const legacyTaskUniqueName = 'hourly-reminder';
  static const _nativeChannel = MethodChannel('fullbright_track/step_service');

  static Future<void> scheduleFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    await schedule(
      enabled: prefs.getBool(enabledKey) ?? true,
      minSteps: prefs.getInt(minStepsKey) ?? 100,
    );
  }

  static Future<void> schedule({
    required bool enabled,
    required int minSteps,
  }) async {
    final safeMinSteps = normalizeMinSteps(minSteps);

    await Workmanager().cancelByUniqueName(taskUniqueName);
    await Workmanager().cancelByUniqueName(legacyTaskUniqueName);

    if (!enabled) {
      await _cancelNativeReminders();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(minStepsKey, safeMinSteps);

    await _scheduleNativeReminders();
    await Workmanager().registerPeriodicTask(
      taskUniqueName,
      StepsReminderWorker.taskName,
      frequency: const Duration(hours: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  static int normalizeMinSteps(int minSteps) {
    return minSteps < 100 ? 100 : minSteps;
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
