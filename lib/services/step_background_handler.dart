import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StepBackgroundHandler extends TaskHandler {
  StreamSubscription<StepCount>? _stepStream;

  // ================= STEP STATE =================

  int _steps = 0;

  int _baseline = 0;

  int _lastRawSteps = 0;

  int _lastSavedSteps = 0;

  DateTime _lastSaveTime = DateTime.now();

  String _currentDay = '';

  // ================= SAVE =================

  Timer? _saveTimer;

  bool _syncing = false;

  List<Map<String, dynamic>> _offlineQueue = [];

  // ================= START =================

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _loadLocalState();

    await _loadQueue();

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Step Tracker Active',
      notificationText: 'Restoring tracking...',
    );

    _stepStream = Pedometer.stepCountStream.listen(
      _onStepEvent,
      onError: (e) {
        debugPrint("Background pedometer error: $e");
      },
    );
  }

  // ================= STEP EVENT =================

  Future<void> _onStepEvent(StepCount event) async {
    final rawSteps = event.steps;

    final today = _todayKey();

    // ================= MIDNIGHT RESET =================

    if (_currentDay != today) {
      _currentDay = today;

      _baseline = rawSteps;

      _steps = 0;

      await _persistLocalState();
    }

    // ================= INITIALIZE BASELINE =================

    if (_baseline == 0) {
      _baseline = rawSteps;
    }

    // ================= RESTART SAFETY =================

    if (rawSteps < _lastRawSteps) {
      _baseline = rawSteps;
    }

    _lastRawSteps = rawSteps;

    // ================= CALCULATE TODAY STEPS =================

    _steps = rawSteps - _baseline;

    if (_steps < 0) {
      _steps = 0;
    }

    // ================= IMMEDIATE LOCAL SAVE =================

    await _persistLocalState();

    // ================= UPDATE NOTIFICATION =================

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Step Tracker Active',
      notificationText: '$_steps steps today',
    );

    // ================= QUEUE SAVE =================

    _queueSave();
  }

  // ================= SAVE QUEUE =================

  void _queueSave() {
    _saveTimer?.cancel();

    _saveTimer = Timer(const Duration(seconds: 5), () async {
      // ================= SAVE LOCAL =================

      await _persistLocalState();

      // ================= THROTTLE FIRESTORE =================

      if ((_steps - _lastSavedSteps).abs() < 10 &&
          DateTime.now().difference(_lastSaveTime).inSeconds < 20) {
        return;
      }

      _lastSavedSteps = _steps;

      _lastSaveTime = DateTime.now();

      await _enqueueSave();
    });
  }

  // ================= ENQUEUE =================

  Future<void> _enqueueSave() async {
    final today = _todayKey();

    // ================= REMOVE OLD ENTRY FOR TODAY =================

    _offlineQueue.removeWhere((e) => e['day'] == today);

    // ================= CLEAN OLD DATA =================

    _offlineQueue.removeWhere((e) {
      final ts = e['timestamp'] ?? 0;

      return DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(ts))
              .inDays >
          7;
    });

    // ================= ADD UPDATED ENTRY =================

    _offlineQueue.add({
      'day': today,
      'steps': _steps,
      'baseline': _baseline,
      'lastRawSteps': _lastRawSteps,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    await _persistQueue();

    _syncQueue();
  }

  // ================= LOAD QUEUE =================

  Future<void> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString('steps_queue');

    if (raw != null) {
      final List decoded = jsonDecode(raw);

      _offlineQueue = decoded.cast<Map<String, dynamic>>();
    }
  }

  // ================= PERSIST QUEUE =================

  Future<void> _persistQueue() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('steps_queue', jsonEncode(_offlineQueue));
  }

  // ================= SYNC =================

  Future<void> _syncQueue() async {
    if (_syncing) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    _syncing = true;

    try {
      while (_offlineQueue.isNotEmpty) {
        final item = _offlineQueue.first;

        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('steps')
            .doc(item['day']);

        final doc = await ref.get();

        final remoteData = doc.data();

        final remoteSteps = (remoteData?['steps'] as num?)?.toInt() ?? 0;

        final merged = item['steps'] > remoteSteps
            ? item['steps']
            : remoteSteps;

        await ref.set({
          'steps': merged,
          'baseline': item['baseline'],
          'lastRawSteps': item['lastRawSteps'],
          'updatedAt': FieldValue.serverTimestamp(),
          'deviceUpdatedAt': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));

        _offlineQueue.removeAt(0);

        await _persistQueue();
      }
    } catch (e) {
      debugPrint("Background sync error: $e");
    } finally {
      _syncing = false;
    }
  }

  // ================= LOCAL STATE =================

  Future<void> _persistLocalState() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('bg_steps', _steps);

    await prefs.setInt('bg_baseline', _baseline);

    await prefs.setInt('bg_last_raw', _lastRawSteps);

    await prefs.setString('bg_day', _currentDay);
  }

  Future<void> _loadLocalState() async {
    final prefs = await SharedPreferences.getInstance();

    _steps = prefs.getInt('bg_steps') ?? 0;

    _baseline = prefs.getInt('bg_baseline') ?? 0;

    _lastRawSteps = prefs.getInt('bg_last_raw') ?? 0;

    _currentDay = prefs.getString('bg_day') ?? '';
  }

  // ================= DATE =================

  String _todayKey() {
    final now = DateTime.now();

    return "${now.year}-"
        "${now.month.toString().padLeft(2, '0')}-"
        "${now.day.toString().padLeft(2, '0')}";
  }

  // ================= DESTROY =================

  @override
  Future<void> onDestroy(DateTime timestamp, bool isStopped) async {
    await _stepStream?.cancel();

    _saveTimer?.cancel();
  }

  // ================= REQUIRED =================

  @override
  void onRepeatEvent(DateTime timestamp) {}
}
