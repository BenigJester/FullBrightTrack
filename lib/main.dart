import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/auth_wrapper.dart';
import 'package:workmanager/workmanager.dart';
import 'services/hourly_worker.dart';
import 'services/notification_service.dart';
import 'package:provider/provider.dart';
import 'models/app_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await NotificationService.initialize();

  Workmanager().initialize(HourlyWorker.callbackDispatcher);

  Workmanager().registerPeriodicTask(
    'hourly-reminder',
    HourlyWorker.taskName,
    frequency: const Duration(hours: 1),
  );

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'step_channel',
      channelName: 'Step Tracker',
      channelDescription: 'Tracks steps in background',
      channelImportance: NotificationChannelImportance.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(1000),
      autoRunOnBoot: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppData())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthWrapper(),
    );
  }
}
