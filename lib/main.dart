import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_wrapper.dart';
import 'services/app_check_service.dart';
import 'services/app_navigator_service.dart';
import 'services/notification_service.dart';
import 'package:provider/provider.dart';
import 'models/app_data.dart';
import 'widgets/internet_guard.dart';

@pragma('vm:entry-point')
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await AppCheckService.activate();

  await NotificationService.initialize();

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
    return MaterialApp(
      navigatorKey: AppNavigatorService.navigatorKey,
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          InternetGuard(child: child ?? const SizedBox.shrink()),
      home: const AuthWrapper(),
    );
  }
}
