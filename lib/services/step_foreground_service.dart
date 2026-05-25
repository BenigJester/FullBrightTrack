import 'package:flutter/services.dart';

class StepForegroundService {
  static const MethodChannel _channel = MethodChannel(
    'fullbright_track/step_service',
  );

  static Future<void> start() async {
    await _channel.invokeMethod<bool>('start');
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<bool>('stop');
  }

  static Future<bool> isRunning() async {
    return await _channel.invokeMethod<bool>('isRunning') ?? false;
  }

  static Future<Map<String, dynamic>> getCurrentState() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getCurrentState',
    );

    return result ?? <String, dynamic>{};
  }
}
