import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'admin_alert_service.dart';
import 'journal_service.dart';
import 'moodscreen_service.dart';
import 'steps_service.dart';

class LogoutService {
  const LogoutService._();

  static final ValueNotifier<bool> isLoggingOut = ValueNotifier<bool>(false);

  static Future<void> logout() async {
    if (isLoggingOut.value) return;

    isLoggingOut.value = true;

    try {
      await Future<void>.delayed(Duration.zero);

      await StepsService.instance.fullLogoutCleanup();
      await AdminAlertService.stopAdminAlertListener();
      await JournalService.dispose();
      await MoodService.instance.flushPendingSave();
      MoodService.instance.dispose();

      await Future<void>.delayed(Duration.zero);
      await FirebaseAuth.instance.signOut();
      isLoggingOut.value = false;
    } catch (_) {
      isLoggingOut.value = false;
      rethrow;
    }
  }
}
