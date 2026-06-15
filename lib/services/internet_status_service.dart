import 'package:flutter/services.dart';

enum InternetProblemType {
  none,
  airplaneMode,
  noConnection,
  wifiNoInternet,
  mobileDataOff,
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

  static Future<InternetStatus> check() async {
    final native = await _nativeStatus();
    if (native != null) {
      return _problemFromNative(native);
    }

    return InternetStatus.ok;
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
