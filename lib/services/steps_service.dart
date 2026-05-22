import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../models/app_data.dart';

class StepsService with WidgetsBindingObserver {
  HealthInsights? _latestInsights;
  // ================= SINGLETON =================

  static final StepsService instance = StepsService._internal();

  factory StepsService() => instance;

  StepsService._internal();

  // ================= CORE =================

  int _baseline = 0;
  int _initialSteps = 0;
  int _lastRawSteps = 0;

  bool _baselineSet = false;
  String _currentDay = "";

  bool _ready = false;

  int _steps = 0;

  static const int maxStepSpike = 3000;

  bool _processing = false;
  int _anchorSteps = 0;

  // ================= STATS =================

  double _calories = 0;
  double _distance = 0;

  final int _goal = 4000;
  final int _calorieGoal = 300;

  // ================= STREAM =================

  StreamSubscription<StepCount>? _stepStream;

  // ================= SAVE CONTROL =================

  Timer? _saveTimer;

  int _lastSavedSteps = 0;
  DateTime _lastSaveTime = DateTime.now();

  // ================= OFFLINE QUEUE =================

  List<Map<String, dynamic>> _offlineQueue = [];

  bool _syncing = false;

  // ================= DEBUG =================

  String _debugText = "Waiting...";

  // ================= APPDATA =================

  AppData? _appData;

  // ================= PUBLIC GETTERS =================

  int get steps => _steps;

  double get calories => _calories;

  double get distance => _distance;

  int get goal => _goal;

  int get calorieGoal => _calorieGoal;

  String get debugText => _debugText;

  bool get ready => _ready;

  // ================= INIT =================

  Future<void> initialize(AppData appData) async {
    _appData = appData;

    WidgetsBinding.instance.addObserver(this);

    await Future.wait([_loadQueue(), _loadToday()]);

    Future.microtask(() => getHealthInsights(_goal));

    _initPedometer();

    Timer.periodic(const Duration(seconds: 15), (_) {
      _syncQueue();
    });
  }

  // =================== FOREGROUND SYNC ===============

  void _syncForegroundTask() {
    FlutterForegroundTask.sendDataToTask({"steps": _steps, "day": _currentDay});
  }

  // ================= LOGOUT CLEAN UP ===================

  Future<void> fullLogoutCleanup() async {
    // 1. Stop foreground service (IMPORTANT)
    await FlutterForegroundTask.stopService();

    // 2. Reset StepsService state
    StepsService.instance.resetAllLocalState();

    // 3. Clear SharedPreferences (ALL step)
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('bg_steps');
    await prefs.remove('bg_baseline');
    await prefs.remove('bg_last_raw');
    await prefs.remove('bg_day');
    await prefs.remove('steps_queue');
  }

  // =============== RESET ALL LOCAL DATA =================

  Future<void> resetAllLocalState() async {
    _steps = 0;
    _baseline = 0;
    _initialSteps = 0;
    _lastRawSteps = 0;
    _anchorSteps = 0;

    _baselineSet = false;
    _currentDay = "";
    _ready = false;

    _offlineQueue.clear();
    _latestInsights = null;

    _debugText = "RESET AFTER LOGOUT";

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // optional FULL wipe if app is single-user

    _pushToAppData();
  }

  // ================ LOCAL SYNC ===============

  Future<void> _persistRealtimeLocal() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('bg_steps', _steps);

    await prefs.setInt('bg_baseline', _baseline);

    await prefs.setInt('bg_last_raw', _lastRawSteps);

    await prefs.setString('bg_day', _currentDay);

    await prefs.setInt('bg_anchor', _anchorSteps);
  }

  // ================= DISPOSE =================

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _stepStream?.cancel();

    _saveTimer?.cancel();

    _enqueueSave();
  }

  // ================= APP LIFECYCLE =================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _enqueueSave();
    }
  }

  // ================= DATE =================

  String _todayKey() {
    final now = DateTime.now();

    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  // ================= PEDOMETER =================

  void _initPedometer() {
    _stepStream = Pedometer.stepCountStream.listen((event) async {
      if (_processing || !_ready) return;

      _processing = true;

      try {
        final today = _todayKey();
        await _processStep(event, today);
        _queueSave();
      } finally {
        _processing = false;
      }
    });
  }

  // ================= PROCESS STEP =================

  Future<void> _processStep(StepCount event, String today) async {
    final raw = event.steps;

    // ================= NEW DAY =================

    if (_currentDay != today) {
      _currentDay = today;

      _baseline = raw;
      _initialSteps = 0;
      _steps = 0;

      _lastRawSteps = raw;
      _baselineSet = true;

      _debugText = "🌙 NEW DAY RESET\nRAW: $raw";

      _updateStats();

      await _persistRealtimeLocal();

      _syncForegroundTask();

      _pushToAppData();

      getHealthInsights(_goal);

      _enqueueSave();

      return;
    }

    // ================= FIRST INIT =================

    if (!_baselineSet) {
      _baseline = raw;

      _anchorSteps = _steps;

      _lastRawSteps = raw;
      _baselineSet = true;

      await _persistRealtimeLocal();
      _syncForegroundTask();
      _pushToAppData();

      return;
    }

    // ================= SENSOR RESET =================

    if (raw < _lastRawSteps) {
      _initialSteps = _steps;

      _anchorSteps = _steps;

      _baseline = raw;

      _lastRawSteps = raw;

      _debugText =
          "🔁 SENSOR RESET\n"
          "RAW: $raw\n"
          "SHIFT BASELINE\n"
          "INIT: $_initialSteps";

      await _persistRealtimeLocal();

      _syncForegroundTask();

      _pushToAppData();

      return;
    }

    final diffRaw = raw - _lastRawSteps;

    // ================= SPIKE DETECTION =================

    if (diffRaw > maxStepSpike) {
      _debugText =
          "⚠️ SPIKE IGNORED\n"
          "RAW: $raw\n"
          "LAST: $_lastRawSteps\n"
          "DIFF: $diffRaw";

      await _persistRealtimeLocal();

      _syncForegroundTask();

      _pushToAppData();

      return;
    }

    // ================= NORMAL COMPUTE =================

    final delta = max(0, raw - _baseline);

    final computed = max(0, _anchorSteps + delta);

    _steps = computed;

    _lastRawSteps = raw;

    _updateStats();

    _debugText =
        "RAW: $raw\n"
        "BASE: $_baseline\n"
        "LAST: $_lastRawSteps\n"
        "DELTA: $delta\n"
        "TOTAL: $_steps";

    await _persistRealtimeLocal();

    _syncForegroundTask();

    _pushToAppData();
  }

  // ================= UPDATE APP DATA =================

  void _pushToAppData() {
    if (_appData == null) return;

    _appData!.updateStepsData(
      steps: _steps,
      caloriesValue: _calories,
      distanceValue: _distance,
      debug: _debugText,

      baseline: _baseline,
      initialSteps: _initialSteps,
      lastRawSteps: _lastRawSteps,
      baselineSet: _baselineSet,
      currentDay: _currentDay,
      ready: _ready,

      currentStreak: _latestInsights?.currentStreak ?? 0,
      longestStreak: _latestInsights?.longestStreak ?? 0,
      trend: _latestInsights?.trend ?? "stable",
      trendPercent: _latestInsights?.trendPercent ?? 0,
      trendLabel: _latestInsights?.trendLabel ?? "",
      insights: _latestInsights?.insights ?? [],
    );
  }

  // ================= LOAD TODAY =================

  Future<void> _loadToday() async {
    final user = FirebaseAuth.instance.currentUser;

    final prefs = await SharedPreferences.getInstance();

    final today = _todayKey();

    _currentDay = today;

    // ================= LOCAL REALTIME CACHE =================

    final localDay = prefs.getString('bg_day') ?? '';

    final localSteps = prefs.getInt('bg_steps') ?? 0;

    final localBaseline = prefs.getInt('bg_baseline') ?? 0;

    final localLastRaw = prefs.getInt('bg_last_raw') ?? 0;

    _anchorSteps = prefs.getInt('bg_anchor') ?? 0;

    int firestoreSteps = 0;

    int firestoreBaseline = 0;

    int firestoreLastRaw = 0;

    // ================= FIRESTORE =================

    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('steps')
            .doc(today)
            .get();

        if (doc.exists) {
          firestoreSteps = (doc.data()?['steps'] as num?)?.toInt() ?? 0;

          firestoreBaseline = (doc.data()?['baseline'] as num?)?.toInt() ?? 0;

          firestoreLastRaw =
              (doc.data()?['lastRawSteps'] as num?)?.toInt() ?? 0;
        }
      } catch (e) {
        debugPrint("Firestore preload failed: $e");
      }
    }

    // ================= MERGE STRATEGY =================

    final validLocal = localDay == today;

    final mergedSteps = validLocal
        ? max(localSteps, firestoreSteps)
        : firestoreSteps;

    _steps = mergedSteps;

    // ================= PREFER LOCAL REALTIME VALUES =================

    if (validLocal && localBaseline > 0) {
      _baseline = localBaseline;

      _lastRawSteps = localLastRaw;
    } else {
      _baseline = firestoreBaseline;

      _lastRawSteps = firestoreLastRaw;
    }

    _anchorSteps = localBaseline > 0 ? localBaseline : firestoreBaseline;

    _initialSteps = _steps;

    // ================= STATS =================

    _updateStats();

    // ================= READY =================

    _baselineSet = false;

    _ready = true;

    _debugText =
        "LOAD COMPLETE\n"
        "LOCAL: $localSteps\n"
        "FIRESTORE: $firestoreSteps\n"
        "MERGED: $_steps";

    _pushToAppData();
  }

  // ================= UPDATE STATS =================

  void _updateStats() {
    _distance = _steps * 0.0008;

    _calories = _steps * 0.04;
  }

  // ================= SAVE QUEUE =================

  void _queueSave() {
    _saveTimer?.cancel();

    _saveTimer = Timer(const Duration(seconds: 2), () {
      if ((_steps - _lastSavedSteps).abs() < 10 &&
          DateTime.now().difference(_lastSaveTime).inSeconds < 20) {
        return;
      }

      _lastSavedSteps = _steps;

      _lastSaveTime = DateTime.now();

      _enqueueSave();
    });
  }

  Future<void> _enqueueSave() {
    final today = _todayKey();

    _offlineQueue.removeWhere((e) => e['day'] == today);

    _offlineQueue.add({
      'day': today,
      'steps': _steps,
      'baseline': _baseline,
      'lastRawSteps': _lastRawSteps,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    return _persistQueue().then((_) {
      _syncQueue();
    });
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

  // ================= SAVE QUEUE =================

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

        int remote = doc.data()?['steps'] ?? 0;

        int merged = item['steps'] > remote ? item['steps'] : remote;

        final remoteBaseline = doc.data()?['baseline'] ?? 0;

        await ref.set({
          'steps': merged,
          'baseline': remoteBaseline == 0 ? item['baseline'] : remoteBaseline,
          'lastRawSteps': item['lastRawSteps'],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        _offlineQueue.removeAt(0);

        await _persistQueue();
      }
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }

  // ================= HEALTH INSIGHTS =================

  Future<HealthInsights> getHealthInsights(int goal) async {
    final data = await _getLastNDaysSteps(30);

    final streaks = _calculateStreaks(data, goal);

    final trendData = _calculateTrend(data);

    final insights = _generateInsights(
      currentStreak: streaks["current"]!,
      longestStreak: streaks["longest"]!,
      trend: trendData["trend"],
      percent: trendData["percent"],
      data: data,
      goal: goal,
    );

    final result = HealthInsights(
      currentStreak: streaks["current"]!,
      longestStreak: streaks["longest"]!,
      trend: trendData["trend"],
      trendPercent: trendData["percent"],
      trendLabel: trendData["label"],
      insights: insights,
    );

    _latestInsights = result;

    // ================= UPDATE APP DATA =================

    _pushToAppData();

    return result;
  }

  // ================= LOAD LAST N DAYS =================

  Future<Map<String, int>> _getLastNDaysSteps(int days) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return {};

    final now = DateTime.now();

    final start = now.subtract(Duration(days: days - 1));

    final dates = _generateDateRange(start, now);

    final futures = dates.map((date) {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('steps')
          .doc(date)
          .get()
          .then((doc) {
            return MapEntry(date, (doc.data()?['steps'] as num?)?.toInt() ?? 0);
          });
    });

    final entries = await Future.wait(futures);

    final result = Map<String, int>.fromEntries(entries);

    // merge offline queue
    for (final item in _offlineQueue) {
      if (result.containsKey(item['day'])) {
        result[item['day']] = item['steps'];
      }
    }

    return result;
  }

  // ================= DATE RANGE =================

  List<String> _generateDateRange(DateTime start, DateTime end) {
    final dates = <String>[];

    DateTime current = start;

    while (!current.isAfter(end)) {
      dates.add(
        "${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}",
      );

      current = current.add(const Duration(days: 1));
    }

    return dates;
  }

  // ================= STREAKS =================

  Map<String, int> _calculateStreaks(Map<String, int> data, int goal) {
    final dates = data.keys.toList()..sort();

    int currentStreak = 0;

    int longestStreak = 0;

    int tempStreak = 0;

    for (int i = 0; i < dates.length; i++) {
      final steps = data[dates[i]] ?? 0;

      if (steps >= goal) {
        tempStreak++;

        longestStreak = tempStreak > longestStreak ? tempStreak : longestStreak;
      } else {
        tempStreak = 0;
      }
    }

    for (int i = dates.length - 1; i >= 0; i--) {
      if ((data[dates[i]] ?? 0) >= goal) {
        currentStreak++;
      } else {
        break;
      }
    }

    return {"current": currentStreak, "longest": longestStreak};
  }

  // ================= TREND =================

  Map<String, dynamic> _calculateTrend(Map<String, int> data) {
    final dates = data.keys.toList()..sort();

    if (dates.length < 14) {
      return {"trend": "stable", "percent": 0.0, "label": "Not enough data"};
    }

    final last7 = dates.sublist(dates.length - 7);

    final prev7 = dates.sublist(dates.length - 14, dates.length - 7);

    int sumLast = last7.fold(0, (s, d) => s + (data[d] ?? 0));

    int sumPrev = prev7.fold(0, (s, d) => s + (data[d] ?? 0));

    if (sumLast == 0 && sumPrev == 0) {
      return {"trend": "stable", "percent": 0.0, "label": "No activity"};
    }

    if (sumPrev == 0 && sumLast > 0) {
      return {"trend": "up", "percent": 100.0, "label": "Started"};
    }

    if (sumPrev > 0 && sumLast == 0) {
      return {"trend": "down", "percent": -100.0, "label": "Stopped"};
    }

    final diff = sumLast - sumPrev;

    final percent = (diff / sumPrev) * 100;

    String trend;

    String label;

    if (percent > 5) {
      trend = "up";

      label = "Improving";
    } else if (percent < -5) {
      trend = "down";

      label = "Declining";
    } else {
      trend = "stable";

      label = "Stable";
    }

    return {"trend": trend, "percent": percent, "label": label};
  }

  // ================= INSIGHTS =================

  List<String> _generateInsights({
    required int currentStreak,
    required int longestStreak,
    required String trend,
    required double percent,
    required Map<String, int> data,
    required int goal,
  }) {
    List<String> insights = [];

    if (currentStreak >= 3) {
      insights.add("🔥 You're on a $currentStreak-day streak!");
    }

    if (currentStreak == 0) {
      insights.add("Let's get moving today to start a new streak.");
    }

    if (currentStreak > 0 && currentStreak >= longestStreak - 1) {
      insights.add("You're close to beating your longest streak!");
    }

    if (trend == "up" && percent > 0 && percent != 100) {
      insights.add(
        "📈 You're improving by ${percent.toStringAsFixed(1)}% this week.",
      );
    } else if (trend == "down" && percent < 0 && percent != -100) {
      insights.add(
        "📉 Activity dropped by ${percent.abs().toStringAsFixed(1)}%.",
      );
    }

    int weekday = 0;

    int weekend = 0;

    data.forEach((date, steps) {
      final d = DateTime.parse(date);

      if (d.weekday >= 6) {
        weekend += steps;
      } else {
        weekday += steps;
      }
    });

    if (weekend > weekday) {
      insights.add("You tend to be more active on weekends.");
    }

    final activeDays = data.values.where((s) => s >= goal).length;

    if (activeDays >= data.length * 0.7) {
      insights.add("💪 You're consistently hitting your goal.");
    }

    return insights;
  }
}

// ================= HEALTH INSIGHTS MODEL =================

class HealthInsights {
  final int currentStreak;
  final int longestStreak;
  final String trend;
  final double trendPercent;
  final String trendLabel;
  final List<String> insights;

  HealthInsights({
    required this.currentStreak,
    required this.longestStreak,
    required this.trend,
    required this.trendPercent,
    required this.trendLabel,
    required this.insights,
  });
}
