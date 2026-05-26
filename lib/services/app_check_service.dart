import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

class AppCheckService {
  const AppCheckService._();

  static const _useDebugProvider = bool.fromEnvironment(
    'USE_APP_CHECK_DEBUG',
    defaultValue: kDebugMode,
  );
  static const _debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

  static Future<void> activate() {
    final debugToken = _debugToken.trim().isEmpty ? null : _debugToken.trim();

    return FirebaseAppCheck.instance.activate(
      providerAndroid: _useDebugProvider
          ? AndroidDebugProvider(debugToken: debugToken)
          : const AndroidPlayIntegrityProvider(),
      providerApple: _useDebugProvider
          ? AppleDebugProvider(debugToken: debugToken)
          : const AppleDeviceCheckProvider(),
    );
  }
}
