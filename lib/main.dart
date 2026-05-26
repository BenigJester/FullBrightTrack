import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_wrapper.dart';
import 'package:workmanager/workmanager.dart';
import 'services/app_check_service.dart';
import 'services/hourly_worker.dart';
import 'services/notification_service.dart';
import 'services/reminder_scheduler_service.dart';
import 'package:provider/provider.dart';
import 'models/app_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await AppCheckService.activate();

  await NotificationService.initialize();

  Workmanager().initialize(HourlyWorker.callbackDispatcher);
  await ReminderSchedulerService.scheduleFromPreferences();

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
