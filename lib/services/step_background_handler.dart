import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:pedometer/pedometer.dart';
import 'step_local_store.dart';

class StepBackgroundHandler extends TaskHandler {
  int _lastNotificationSteps = -1;
  String _currentDay = "";
  StepLocalState? _state;
  StreamSubscription<StepCount>? _stepSubscription;
  bool _processing = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _state = await StepLocalStore.load();

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Step Tracker Active',
      notificationText: '${_state?.steps ?? 0} steps today',
    );

    _sendStateToMain();
    _startPedometer();

    debugPrint("Foreground service started");
  }

  // ================= COMMANDS FROM MAIN APP =================
  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;

    final command = data['command'];

    if (command == 'refresh') {
      _sendStateToMain();
    }
  }

  // ================= PEDOMETER =================
  void _startPedometer() {
    _stepSubscription?.cancel();

    _stepSubscription = Pedometer.stepCountStream.listen(
      (event) async {
        if (_processing) return;

        _processing = true;

        try {
          final current = _state ?? await StepLocalStore.load();
          _state = await StepLocalStore.processStep(current, event);

          await StepLocalStore.enqueueSave(_state!);

          await _updateNotification(_state!.steps, _state!.day);
          _sendStateToMain();
        } finally {
          _processing = false;
        }
      },
      onError: (error) {
        debugPrint('Step stream error: $error');
      },
      cancelOnError: false,
    );
  }

  void _sendStateToMain() {
    final state = _state;
    if (state == null) return;

    FlutterForegroundTask.sendDataToMain(state.toTaskData());
  }

  // ================= UPDATE NOTIFICATION =================
  Future<void> _updateNotification(int steps, String day) async {
    // reset counter if new day
    if (_currentDay != day) {
      _currentDay = day;
      _lastNotificationSteps = -1;
    }

    // avoid unnecessary UI updates
    if (steps == _lastNotificationSteps) return;

    _lastNotificationSteps = steps;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Step Tracker Active',
      notificationText: '$steps steps today',
    );
  }

  // ================= FALLBACK (optional periodic refresh) =================
  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (_state != null) {
      await StepLocalStore.persist(_state!);
      await StepLocalStore.enqueueSave(_state!);
      await _updateNotification(_state!.steps, _state!.day);
      _sendStateToMain();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isStopped) async {
    await _stepSubscription?.cancel();

    if (_state != null) {
      await StepLocalStore.persist(_state!);
      await StepLocalStore.enqueueSave(_state!);
    }

    debugPrint("Foreground service destroyed");
  }
}
