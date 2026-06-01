import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/loading_screen.dart';
import '../screens/login_screen.dart';
import 'admin_alert_service.dart';
import 'logout_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LogoutService.isLoggingOut,
      builder: (context, isLoggingOut, _) {
        if (isLoggingOut) {
          return LoginTab();
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            // Loading
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // If logged in -> Home
            if (snapshot.hasData) {
              return LoadingScreen();
            }

            unawaited(AdminAlertService.stopAdminAlertListener());

            // If not logged in -> Login
            return LoginTab();
          },
        );
      },
    );
  }
}
