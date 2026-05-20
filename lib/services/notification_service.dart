import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await notifications.initialize(settings: settings);
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
      body: '$steps steps today 🚶',
      notificationDetails: details,
    );
  }
}
