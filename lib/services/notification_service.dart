import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

import '../screens/admin_monitoring_screen.dart';
import 'app_navigator_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTap(response.payload);
      },
    );
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'admin_safety_alerts',
            'Admin Safety Alerts',
            description: 'Privacy-safe alerts for admin review',
            importance: Importance.high,
          ),
        );
  }

  static Future<void> showHourlySteps(int steps) async {
    const androidDetails = AndroidNotificationDetails(
      'hourly_steps',
      'Hourly Step Reminder',
      channelDescription: 'Hourly wellness reminders',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      onlyAlertOnce: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await notifications.show(
      id: 100,
      title: 'Step Reminder',
      body: '$steps steps today \u{1F6B6}',
      notificationDetails: details,
    );
  }

  static Future<void> showAdminSafetyAlert({
    required String displayName,
    required String rank,
    String? userId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'admin_safety_alerts',
      'Admin Safety Alerts',
      channelDescription: 'Privacy-safe alerts for admin review',
      importance: Importance.high,
      priority: Priority.high,
    );

    await notifications.show(
      id: 200,
      title: 'Wellness signal needs review',
      body: '$displayName has a $rank stress signal. Open Admin Monitoring.',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: jsonEncode({
        'type': 'admin_safety_alert',
        if (userId != null && userId.isNotEmpty) 'userId': userId,
      }),
    );
  }

  static void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded['type'] != 'admin_safety_alert') return;
      final userId = decoded['userId'] as String?;
      final context = AppNavigatorService.context;
      if (context == null || !context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdminMonitoringScreen(
            initialUserId: userId == null || userId.isEmpty ? null : userId,
          ),
        ),
      );
    } catch (_) {
      return;
    }
  }
}
