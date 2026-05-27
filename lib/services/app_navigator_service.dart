import 'package:flutter/material.dart';

class AppNavigatorService {
  const AppNavigatorService._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get context => navigatorKey.currentContext;
}
