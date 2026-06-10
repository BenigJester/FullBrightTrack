import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/auth_wrapper.dart';
import 'services/app_check_service.dart';
import 'services/app_navigator_service.dart';
import 'services/notification_service.dart';
import 'package:provider/provider.dart';
import 'models/app_data.dart';
import 'widgets/internet_guard.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationService.initialize();

  final type = message.data['type'] as String?;
  if (type != 'admin_safety_alert' && type != 'admin_notification_test') {
    return;
  }

  if (message.notification != null) return;

  final title = message.data['title'] as String? ?? 'FullBrightTrack alert';
  final body =
      message.data['body'] as String? ??
      (type == 'admin_safety_alert'
          ? 'A wellness signal needs review.'
          : 'Admin notification delivery is working.');

  await NotificationService.showAdminSafetyNotification(
    title: title,
    body: body,
    userId: message.data['userId'] as String?,
  );
}

@pragma('vm:entry-point')
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
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
