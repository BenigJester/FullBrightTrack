import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

enum InternetProblemType {
  none,
  airplaneMode,
  noConnection,
  wifiNoInternet,
  mobileDataOff,
  unreachable,
}

class InternetStatus {
  const InternetStatus({
    required this.type,
    required this.title,
    required this.message,
    this.downstreamKbps = 0,
  });

  final InternetProblemType type;
  final String title;
  final String message;
  final int downstreamKbps;

  bool get isOk => type == InternetProblemType.none;

  static const ok = InternetStatus(
    type: InternetProblemType.none,
    title: 'Connected',
    message: 'Internet connection is available.',
  );
}

class InternetStatusService {
  const InternetStatusService._();

  static const _channel = MethodChannel('fullbright_track/connectivity');
  static const _probeUrl = String.fromEnvironment(
    'FULLBRIGHT_BACKEND_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static Future<InternetStatus> check() async {
    final native = await _nativeStatus();
    if (native != null) {
      final nativeProblem = _problemFromNative(native);
      if (!nativeProblem.isOk) return nativeProblem;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final uri = _healthUri();
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      stopwatch.stop();

      if (response.statusCode < 200 || response.statusCode >= 500) {
        return const InternetStatus(
          type: InternetProblemType.unreachable,
          title: 'Online services are unreachable',
          message:
              'Your internet may be connected, but FullBrightTrack cannot reach its online services right now.',
        );
      }

      return InternetStatus.ok;
    } on SocketException {
      return const InternetStatus(
        type: InternetProblemType.noConnection,
        title: 'No internet connection',
        message:
            'FullBrightTrack cannot reach the internet. Turn on Wi-Fi or mobile data, then retry.',
      );
    } on TimeoutException {
      return const InternetStatus(
        type: InternetProblemType.unreachable,
        title: 'Online services are unreachable',
        message:
            'FullBrightTrack cannot reach its online services right now. Check your connection and retry.',
      );
    } catch (_) {
      return const InternetStatus(
        type: InternetProblemType.unreachable,
        title: 'Online services are unreachable',
        message:
            'FullBrightTrack cannot connect to its online services right now. Check your connection and retry.',
      );
    }
  }

  static Uri _healthUri() {
    final base = _probeUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return Uri.parse('http://10.0.2.2:8080/health');
    if (base.endsWith('/stress')) {
      return Uri.parse('${base.substring(0, base.length - 7)}/health');
    }
    return Uri.parse('$base/health');
  }

  static Future<Map<String, dynamic>?> _nativeStatus() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('status');
      return raw;
    } catch (_) {
      return null;
    }
  }

  static InternetStatus _problemFromNative(Map<String, dynamic> status) {
    final airplaneMode = status['airplaneMode'] == true;
    final hasNetwork = status['hasNetwork'] == true;
    final hasInternetCapability = status['hasInternetCapability'] == true;
    final validated = status['validated'] == true;
    final transports = (status['transports'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    if (airplaneMode) {
      return const InternetStatus(
        type: InternetProblemType.airplaneMode,
        title: 'Airplane mode is on',
        message:
            'Turn off airplane mode so AI, account, and admin alert services can reconnect.',
      );
    }

    if (!hasNetwork) {
      return const InternetStatus(
        type: InternetProblemType.mobileDataOff,
        title: 'No Wi-Fi or mobile data',
        message:
            'Your device is not connected to Wi-Fi or mobile data. Reconnect, then retry.',
      );
    }

    if (transports.contains('wifi') && !validated) {
      return const InternetStatus(
        type: InternetProblemType.wifiNoInternet,
        title: 'Wi-Fi has no internet access',
        message:
            'You are connected to Wi-Fi, but it cannot reach the internet. Switch networks or use mobile data.',
      );
    }

    if (!hasInternetCapability || !validated) {
      return const InternetStatus(
        type: InternetProblemType.noConnection,
        title: 'No internet access',
        message:
            'The device has a network connection, but internet access is not available.',
      );
    }

    return InternetStatus.ok;
  }
}
