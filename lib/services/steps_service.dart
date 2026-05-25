import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_data.dart';
import 'step_foreground_service.dart';
import 'step_local_store.dart';

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

  // ================= STATS =================

  double _calories = 0;
  double _distance = 0;

  final int _goal = 4000;
  final int _calorieGoal = 300;

  // ================= SAVE CONTROL =================

  Timer? _syncTimer;
  Timer? _localRefreshTimer;
  Timer? _firestoreSaveTimer;

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

    await _refreshFromLocalCache(syncNow: true);

    Future.microtask(() => getHealthInsights(_goal));

    _localRefreshTimer?.cancel();
    _localRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshFromLocalCache();
    });

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _syncQueue();
    });

    unawaited(_syncQueue());
  }

  Future<void> _refreshFromLocalCache({bool syncNow = false}) async {
    final rawLocal = await _readBestLocalState();
    final local = _mergeLocalWithoutStepRollback(rawLocal);

    if (local.day != _currentDay ||
        local.steps != _steps ||
        local.baseline != _baseline ||
        local.lastRawSteps != _lastRawSteps ||
        local.debugText != _debugText) {
      final stepsChanged = local.steps != _steps;

      _steps = local.steps;
      _baseline = local.baseline;
      _initialSteps = local.initialSteps;
      _lastRawSteps = local.lastRawSteps;
      _baselineSet = local.baselineSet;
      _currentDay = local.day;
      _debugText = local.debugText;
      _ready = true;

      _updateStats();
      _pushToAppData();

      await StepLocalStore.persist(local);
      if (stepsChanged && local.day.isNotEmpty) {
        _queueLocalState(local);
        await _persistQueue();
        _autoSaveTodaySteps(local);
        if (syncNow) {
          await _saveTodayStepsToFirestore(local);
        }
      }
    } else if (syncNow && local.day.isNotEmpty) {
      _queueLocalState(local);
      await _persistQueue();
      await _saveTodayStepsToFirestore(local);
    }
  }

  StepLocalState _mergeLocalWithoutStepRollback(StepLocalState local) {
    final sameDay = local.day.isNotEmpty && local.day == _currentDay;
    if (!sameDay || local.steps >= _steps) {
      return local;
    }

    return StepLocalState(
      steps: _steps,
      baseline: local.baseline > 0 ? local.baseline : _baseline,
      initialSteps: local.initialSteps,
      lastRawSteps: local.lastRawSteps > 0 ? local.lastRawSteps : _lastRawSteps,
      anchorSteps: max(local.anchorSteps, _steps),
      baselineSet: local.baselineSet || _baselineSet,
      day: local.day,
      debugText:
          "Kept Firestore steps ($_steps); native reported lower (${local.steps})",
    );
  }

  void _queueLocalState(StepLocalState state) {
    _offlineQueue.removeWhere((e) => e['day'] == state.day);
    _offlineQueue.add({
      'day': state.day,
      'steps': state.steps,
      'baseline': state.baseline,
      'lastRawSteps': state.lastRawSteps,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<StepLocalState> _readBestLocalState() async {
    final fallback = await StepLocalStore.load();

    try {
      final native = await StepForegroundService.getCurrentState();
      final nativeSteps = _nativeInt(native['steps']);
      final nativeDay = native['day'] as String? ?? '';
      final nativeDebug = native['debugText'] as String? ?? '';

      if (nativeDay.isEmpty && nativeSteps == 0 && nativeDebug.isEmpty) {
        return fallback;
      }

      return StepLocalState(
        steps: nativeSteps,
        baseline: _nativeInt(native['baseline']),
        initialSteps: _nativeInt(native['initialSteps']),
        lastRawSteps: _nativeInt(native['lastRawSteps']),
        anchorSteps: _nativeInt(native['anchorSteps']),
        baselineSet: _nativeInt(native['baseline']) > 0,
        day: nativeDay.isEmpty ? fallback.day : nativeDay,
        debugText: nativeDebug.isEmpty ? fallback.debugText : nativeDebug,
      );
    } catch (e) {
      debugPrint("Native step state read failed: $e");
      return fallback;
    }
  }

  int _nativeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  // ================= LOGOUT CLEAN UP ===================

  Future<void> fullLogoutCleanup() async {
    await _flushCurrentStepsToFirestore();

    await StepForegroundService.stop();

    await StepsService.instance.resetAllLocalState();

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('bg_steps');
    await prefs.remove('bg_baseline');
    await prefs.remove('bg_last_raw');
    await prefs.remove('bg_initial_steps');
    await prefs.remove('bg_day');
    await prefs.remove('bg_anchor');
    await prefs.remove('bg_native_running');
    await prefs.remove('steps_queue');
    await prefs.remove('bg_debug');
  }

  Future<void> _flushCurrentStepsToFirestore() async {
    _firestoreSaveTimer?.cancel();
    await _refreshFromLocalCache();

    final day = _currentDay.isEmpty ? _todayKey() : _currentDay;
    final state = StepLocalState(
      steps: _steps,
      baseline: _baseline,
      initialSteps: _initialSteps,
      lastRawSteps: _lastRawSteps,
      anchorSteps: 0,
      baselineSet: _baselineSet,
      day: day,
      debugText: _debugText,
    );

    _queueLocalState(state);
    await _persistQueue();
    await _waitForSyncIdle();
    final saved = await _saveTodayStepsToFirestore(state);
    if (!saved) {
      throw Exception("Could not save today's steps before logout");
    }
  }

  Future<void> _waitForSyncIdle() async {
    for (var attempt = 0; attempt < 20 && _syncing; attempt++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // =============== RESET ALL LOCAL DATA =================

  Future<void> resetAllLocalState() async {
    _steps = 0;
    _baseline = 0;
    _initialSteps = 0;
    _lastRawSteps = 0;
    _baselineSet = false;
    _currentDay = "";
    _ready = false;

    _offlineQueue.clear();
    _latestInsights = null;

    _debugText = "RESET AFTER LOGOUT";

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    _pushToAppData();
  }

  // ================= DISPOSE =================

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _syncTimer?.cancel();
    _localRefreshTimer?.cancel();
    _firestoreSaveTimer?.cancel();

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
    await prefs.reload();

    final today = _todayKey();

    _currentDay = today;

    // ================= LOCAL REALTIME CACHE =================

    final localState = await _readBestLocalState();

    final localDay = localState.day;

    final localSteps = localState.steps;

    final localBaseline = localState.baseline;

    final localLastRaw = localState.lastRawSteps;

    final localInitialSteps = localState.initialSteps;

    final localDebug = localState.debugText;

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

    _initialSteps = validLocal ? localInitialSteps : mergedSteps;

    // ================= STATS =================

    _updateStats();

    // ================= READY =================

    _baselineSet = _baseline > 0;

    _ready = true;

    _debugText =
        "LOAD COMPLETE\n"
        "LOCAL: $localSteps\n"
        "FIRESTORE: $firestoreSteps\n"
        "MERGED: $_steps";

    if (validLocal && localDebug.isNotEmpty) {
      _debugText = localDebug;
    }

    await _seedNativeStateFromCurrent();

    _pushToAppData();
  }

  Future<void> _seedNativeStateFromCurrent() async {
    if (_currentDay.isEmpty) return;

    try {
      await StepForegroundService.seedState(
        steps: _steps,
        baseline: _baseline,
        initialSteps: _initialSteps,
        lastRawSteps: _lastRawSteps,
        anchorSteps: max(_steps, _initialSteps),
        day: _currentDay,
      );
    } catch (e) {
      debugPrint("Native step seed failed: $e");
    }
  }

  // ================= UPDATE STATS =================

  void _updateStats() {
    _distance = StepLocalStore.distanceFor(_steps);

    _calories = StepLocalStore.caloriesFor(_steps);
  }

  Future<void> _enqueueSave() {
    final today = _todayKey();

    _queueLocalState(
      StepLocalState(
        steps: _steps,
        baseline: _baseline,
        initialSteps: _initialSteps,
        lastRawSteps: _lastRawSteps,
        anchorSteps: 0,
        baselineSet: _baselineSet,
        day: today,
        debugText: _debugText,
      ),
    );

    return _persistQueue().then((_) async {
      await _saveCurrentStepsToFirestore();
    });
  }

  void _autoSaveTodaySteps(StepLocalState state) {
    _firestoreSaveTimer?.cancel();
    _firestoreSaveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_saveTodayStepsToFirestore(state));
    });
  }

  Future<bool> _saveCurrentStepsToFirestore() {
    final day = _currentDay.isEmpty ? _todayKey() : _currentDay;

    return _saveTodayStepsToFirestore(
      StepLocalState(
        steps: _steps,
        baseline: _baseline,
        initialSteps: _initialSteps,
        lastRawSteps: _lastRawSteps,
        anchorSteps: 0,
        baselineSet: _baselineSet,
        day: day,
        debugText: _debugText,
      ),
    );
  }

  Future<bool> _saveTodayStepsToFirestore(StepLocalState state) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || state.day.isEmpty) {
      _setDebugStatus("Firestore step save skipped: no signed-in user");
      return false;
    }

    try {
      final safeSteps = state.day == _currentDay ? max(state.steps, _steps) : state.steps;

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('steps')
          .doc(state.day);

      await ref.set({
        'steps': safeSteps,
        'baseline': state.baseline,
        'lastRawSteps': state.lastRawSteps,
        'calories': StepLocalStore.caloriesFor(safeSteps),
        'distance': StepLocalStore.distanceFor(safeSteps),
        'updated_at': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _offlineQueue.removeWhere((entry) => entry['day'] == state.day);
      await _persistQueue();
      _setDebugStatus("Firestore saved $safeSteps steps");
      return true;
    } catch (e) {
      _setDebugStatus("Firestore step save failed: $e");
      return false;
    }
  }

  void _setDebugStatus(String status) {
    _debugText = status;
    _pushToAppData();
    debugPrint(status);
  }

  // ================= LOAD QUEUE =================

  Future<void> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final raw = prefs.getString('steps_queue');

    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _offlineQueue = decoded
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
      }
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

        final remote = (doc.data()?['steps'] as num?)?.toInt() ?? 0;

        final localSteps = (item['steps'] as num?)?.toInt() ?? 0;

        final merged = localSteps > remote ? localSteps : remote;

        final remoteBaseline =
            (doc.data()?['baseline'] as num?)?.toInt() ?? 0;
        final localBaseline = (item['baseline'] as num?)?.toInt() ?? 0;
        final localLastRaw = (item['lastRawSteps'] as num?)?.toInt() ?? 0;

        await ref.set({
          'steps': merged,
          'baseline': remoteBaseline == 0 ? localBaseline : remoteBaseline,
          'lastRawSteps': localLastRaw,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        _offlineQueue.removeAt(0);

        await _persistQueue();
      }
    } catch (e) {
      debugPrint("Step queue sync failed: $e");
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
