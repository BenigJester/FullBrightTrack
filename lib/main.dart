import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
