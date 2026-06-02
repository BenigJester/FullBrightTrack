import 'dart:math';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCheckService {
  const AppCheckService._();

  static const _enabled = bool.fromEnvironment(
    'ENABLE_APP_CHECK',
    defaultValue: true,
  );
  static const _useDebugProvider = bool.fromEnvironment(
    'USE_APP_CHECK_DEBUG',
    defaultValue: kDebugMode,
  );
  static const _debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');
  static const _debugTokenPrefsKey = 'app_check_debug_token';

  static Future<void> activate() async {
    if (!_enabled) {
      debugPrint('Firebase App Check is disabled for this build.');
      return;
    }

    final debugToken = _useDebugProvider ? await _debugTokenForDevice() : null;

    await FirebaseAppCheck.instance.activate(
      providerAndroid: _useDebugProvider
          ? AndroidDebugProvider(debugToken: debugToken)
          : const AndroidPlayIntegrityProvider(),
      providerApple: _useDebugProvider
          ? AppleDebugProvider(debugToken: debugToken)
          : const AppleDeviceCheckProvider(),
    );

    if (_useDebugProvider) {
      debugPrint('Firebase App Check debug provider is active.');
      debugPrint('Firebase App Check debug token to register: $debugToken');
      try {
        final token = await FirebaseAppCheck.instance.getToken(true);
        debugPrint(
          'Firebase App Check debug token request completed: ${token == null ? 'no token returned' : 'token returned'}',
        );
      } catch (error) {
        debugPrint('Firebase App Check debug token request failed: $error');
      }
    }
  }

  static Future<String> _debugTokenForDevice() async {
    final configuredToken = _debugToken.trim();
    if (configuredToken.isNotEmpty) return configuredToken;

    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_debugTokenPrefsKey);
    if (savedToken != null && savedToken.isNotEmpty) return savedToken;

    final generatedToken = _generateUuidV4();
    await prefs.setString(_debugTokenPrefsKey, generatedToken);
    return generatedToken;
  }

  static String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final parts = [
      bytes.sublist(0, 4),
      bytes.sublist(4, 6),
      bytes.sublist(6, 8),
      bytes.sublist(8, 10),
      bytes.sublist(10, 16),
    ];

    return parts.map((part) => part.map(hex).join()).join('-');
  }
}
