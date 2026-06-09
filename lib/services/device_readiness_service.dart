import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'admin_access_service.dart';

class DeviceReadinessService {
  const DeviceReadinessService._();

  static const _channel = MethodChannel('fullbright_track/device_readiness');

  static Future<void> requestStartupNotificationPermission() async {}

  static Future<DeviceReadinessStatus> checkStatus() async {
    final sdkVersion = await _androidSdkVersion();
    final activity = await Permission.activityRecognition.status;
    final notification = await Permission.notification.status;
    final ignoringBatteryOptimizations =
        await _isIgnoringBatteryOptimizations();

    return DeviceReadinessStatus(
      activityRecognitionGranted: sdkVersion != null && sdkVersion < 29
          ? true
          : activity.isGranted,
      notificationGranted: sdkVersion != null && sdkVersion < 33
          ? true
          : notification.isGranted,
      unrestrictedBattery: ignoringBatteryOptimizations ?? true,
    );
  }

  static Future<bool> requestActivityRecognition() async {
    final current = await Permission.activityRecognition.status;
    if (current.isGranted) return true;
    if (_mustUseSettings(current)) return false;

    final nativeGranted = await requestNativeActivityRecognitionFallback();
    if (nativeGranted) return true;

    debugPrint(
      'Activity permission request did not show/grant: '
      '${await permissionDiagnostics()}',
    );
    final next = await Permission.activityRecognition.status;
    return next.isGranted;
  }

  static Future<bool> requestNotificationPermission() async {
    final current = await Permission.notification.status;
    if (current.isGranted) return true;
    if (_mustUseSettings(current)) return false;

    final nativeGranted = await requestNativeNotificationFallback();
    if (nativeGranted) {
      return true;
    }

    debugPrint(
      'Notification permission request did not show/grant: '
      '${await permissionDiagnostics()}',
    );
    final next = await Permission.notification.status;
    return next.isGranted;
  }

  static Future<bool> requestNativeActivityRecognitionFallback() async {
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestActivityRecognition',
      );
      if (granted == true) return true;
    } catch (error) {
      debugPrint('Native activity permission request failed: $error');
    }

    return Permission.activityRecognition.isGranted;
  }

  static Future<bool> requestNativeNotificationFallback() async {
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestPostNotifications',
      );
      if (granted == true) return true;
    } catch (error) {
      debugPrint('Native notification permission request failed: $error');
    }

    return Permission.notification.isGranted;
  }

  static Future<bool> openPermissionSettings() {
    return openAppSettings();
  }

  static Future<Map<String, Object?>> permissionDiagnostics() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'permissionDiagnostics',
      );
      return value ?? const {};
    } catch (error) {
      debugPrint('Permission diagnostics failed: $error');
      return const {};
    }
  }

  static Future<void> registerAdminMessagingToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!AdminAccessService.dataHasAdminAccess(userDoc.data())) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await FirebaseFirestore.instance
          .collection('admin_fcm_tokens')
          .doc(user.uid)
          .collection('tokens')
          .doc(token)
          .set({
            'uid': user.uid,
            'token': token,
            'platform': defaultTargetPlatform.name,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await FirebaseFirestore.instance
            .collection('admin_fcm_tokens')
            .doc(user.uid)
            .collection('tokens')
            .doc(newToken)
            .set({
              'uid': user.uid,
              'token': newToken,
              'platform': defaultTargetPlatform.name,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      });
    } catch (error) {
      if (error is FirebaseException && error.code == 'permission-denied') {
        debugPrint('Admin FCM token registration skipped: permission-denied');
        return;
      }

      debugPrint('Admin FCM token registration failed: $error');
    }
  }

  static Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
    } catch (error) {
      debugPrint('Could not open battery settings: $error');
    }
  }

  static Future<bool> requestUnrestrictedBattery() async {
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
      return await waitForBatteryStatusRefresh();
    } catch (error) {
      debugPrint('Could not request unrestricted battery mode: $error');
      return await isIgnoringBatteryOptimizations();
    }
  }

  static Future<bool> waitForBatteryStatusRefresh() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (await isIgnoringBatteryOptimizations()) return true;
    }
    return false;
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    return await _isIgnoringBatteryOptimizations() ?? true;
  }

  static Future<bool?> _isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _androidSdkVersion() async {
    try {
      return await _channel.invokeMethod<int>('androidSdkVersion');
    } catch (_) {
      return null;
    }
  }

  static bool _mustUseSettings(PermissionStatus status) {
    return status.isPermanentlyDenied || status.isRestricted;
  }
}

class DeviceReadinessStatus {
  const DeviceReadinessStatus({
    required this.activityRecognitionGranted,
    required this.notificationGranted,
    required this.unrestrictedBattery,
  });

  final bool activityRecognitionGranted;
  final bool notificationGranted;
  final bool unrestrictedBattery;

  bool get needsAttention {
    return !activityRecognitionGranted ||
        !notificationGranted ||
        !unrestrictedBattery;
  }

  List<DeviceReadinessIssue> get issues {
    return [
      if (!activityRecognitionGranted)
        const DeviceReadinessIssue(
          title: 'Allow step access',
          description:
              'Needed for daily step tracking, progress, and wellness summaries.',
          iconName: 'directions_walk',
          action: DeviceReadinessAction.activity,
        ),
      if (!notificationGranted)
        const DeviceReadinessIssue(
          title: 'Allow notifications',
          description: 'Needed for step reminders and admin safety alerts.',
          iconName: 'notifications',
          action: DeviceReadinessAction.notification,
        ),
      if (!unrestrictedBattery)
        const DeviceReadinessIssue(
          title: 'Allow background running',
          description:
              'Set battery usage to unrestricted so step tracking can restart after phone reboot.',
          iconName: 'battery_alert',
          action: DeviceReadinessAction.battery,
        ),
    ];
  }
}

enum DeviceReadinessAction { activity, notification, battery }

class DeviceReadinessIssue {
  const DeviceReadinessIssue({
    required this.title,
    required this.description,
    required this.iconName,
    required this.action,
  });

  final String title;
  final String description;
  final String iconName;
  final DeviceReadinessAction action;
}
