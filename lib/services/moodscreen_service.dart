import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'streak_service.dart';
import '../models/app_data.dart';
import 'leaderboard_service.dart';
import 'wellness_signal_service.dart';
import 'genkit_stress_ai_service.dart';

class MoodService {
  // ================= SINGLETON =================

  static final MoodService instance = MoodService._internal();

  factory MoodService() => instance;

  MoodService._internal();

  // ================= APP DATA =================

  AppData? _appData;
  bool _userEditedTodayMood = false;
  String? _lastAppliedExternalMoodKey;
  int? _pendingMoodIndex;
  double? _pendingMoodIntensity;

  // ================= SAVE =================

  Timer? _debounce;
  Timer? _wellnessPublishDebounce;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _aiMoodSubscription;

  // ================= MOODS =================

  final moods = ["\u{1F61E}", "\u{1F642}", "\u{1F604}", "\u{1F929}"];

  // ================= INITIALIZE =================

  Future<void> initialize(AppData appData) {
    _appData = appData;
    _listenForAiMoodAdjustments();

    return loadTodayMood();
  }

  // ================= DISPOSE =================

  void dispose() {
    unawaited(flushPendingSave());
    _wellnessPublishDebounce?.cancel();
    _aiMoodSubscription?.cancel();
    _aiMoodSubscription = null;
  }

  Future<void> flushPendingSave() async {
    _debounce?.cancel();
    _debounce = null;
    final moodIndex = _pendingMoodIndex;
    final intensity = _pendingMoodIntensity;
    if (moodIndex == null || intensity == null) return;

    await _writeMood(
      moodIndex: moodIndex,
      intensity: intensity,
      source: 'manual',
      updateStreaks: true,
    );
    _pendingMoodIndex = null;
    _pendingMoodIntensity = null;
  }

  // ================= DATE =================

  String _todayKey() {
    final now = DateTime.now();

    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  String _moodCachePrefix(String uid, String dateKey) {
    return 'mood_cache_${uid}_$dateKey';
  }

  Future<void> _cacheMood({
    required String uid,
    required String dateKey,
    required int moodIndex,
    required double intensity,
    required String source,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _moodCachePrefix(uid, dateKey);
    await prefs.setInt('${prefix}_index', moodIndex);
    await prefs.setDouble('${prefix}_intensity', intensity);
    await prefs.setInt(
      '${prefix}_updated_ms',
      DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString('${prefix}_source', source);
  }

  Future<_CachedMood?> _cachedMood(String uid, String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _moodCachePrefix(uid, dateKey);
    final moodIndex = prefs.getInt('${prefix}_index');
    final intensity = prefs.getDouble('${prefix}_intensity');
    final updatedMs = prefs.getInt('${prefix}_updated_ms');
    if (moodIndex == null || intensity == null || updatedMs == null) {
      return null;
    }

    return _CachedMood(
      moodIndex: moodIndex.clamp(0, moods.length - 1),
      intensity: intensity.clamp(0.0, 1.0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
      source: prefs.getString('${prefix}_source') ?? 'manual',
    );
  }

  DateTime? _remoteMoodUpdatedAt(Map<String, dynamic>? data) {
    final updatedAt = data?['updated_at'];
    if (updatedAt is Timestamp) return updatedAt.toDate();
    if (updatedAt is String) return DateTime.tryParse(updatedAt);
    return null;
  }

  // ================= LOAD TODAY MOOD =================

  Future<void> loadTodayMood() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || _appData == null) {
      return;
    }

    final today = _todayKey();
    _userEditedTodayMood = false;
    final cached = await _cachedMood(user.uid, today);
    if (cached != null) {
      _appData!.updateMoodData(
        moodIndex: cached.moodIndex,
        moodIntensity: cached.intensity,
      );
    }

    final DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mood')
          .doc(today)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('Today mood load skipped: permission-denied');
        if (cached == null) {
          _appData!.updateMoodData(moodIndex: 1, moodIntensity: 0.5);
        }
        return;
      }

      rethrow;
    }

    if (!doc.exists) {
      if (cached != null) {
        _pendingMoodIndex = cached.moodIndex;
        _pendingMoodIntensity = cached.intensity;
        _userEditedTodayMood = cached.source == 'manual';
        unawaited(flushPendingSave());
        return;
      }
      _appData!.updateMoodData(moodIndex: 1, moodIntensity: 0.5);
      await _applyLatestAiMoodAdjustment();

      return;
    }

    final docData = doc.data();
    final remoteUpdatedAt = _remoteMoodUpdatedAt(docData);
    if (cached != null &&
        (remoteUpdatedAt == null ||
            cached.updatedAt.isAfter(remoteUpdatedAt))) {
      _appData!.updateMoodData(
        moodIndex: cached.moodIndex,
        moodIntensity: cached.intensity,
      );
      _pendingMoodIndex = cached.moodIndex;
      _pendingMoodIntensity = cached.intensity;
      _userEditedTodayMood = cached.source == 'manual';
      unawaited(flushPendingSave());
      return;
    }

    final moodIndex = docData?['mood_index'] ?? 1;
    final intensity = (docData?['intensity'] ?? 0.5).toDouble();
    final source = (docData?['source'] as String?) ?? 'firestore';
    _userEditedTodayMood = source == 'manual';
    _appData!.updateMoodData(moodIndex: moodIndex, moodIntensity: intensity);
    unawaited(
      _cacheMood(
        uid: user.uid,
        dateKey: today,
        moodIndex: moodIndex,
        intensity: intensity,
        source: source,
      ),
    );
    if (!_userEditedTodayMood) {
      await _applyLatestAiMoodAdjustment();
    }
  }

  void _listenForAiMoodAdjustments() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _appData == null) return;

    _aiMoodSubscription?.cancel();
    _aiMoodSubscription = FirebaseFirestore.instance
        .collection('admin_monitoring')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) => _applyAiMoodData(snapshot.data()),
          onError: (Object error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              _aiMoodSubscription?.cancel();
              _aiMoodSubscription = null;
              debugPrint(
                'AI mood adjustment listen skipped: permission-denied',
              );
              return;
            }
          },
        );
  }

  Future<void> _applyLatestAiMoodAdjustment() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _appData == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('admin_monitoring')
          .doc(user.uid)
          .get();
      _applyAiMoodData(snapshot.data());
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('AI mood adjustment load skipped: permission-denied');
        return;
      }

      rethrow;
    }
  }

  void _applyAiMoodData(Map<String, dynamic>? data) {
    if (_appData == null || data == null) return;
    if (_userEditedTodayMood) return;

    final rawMoodIndex = data['aiMoodIndex'];
    final rawIntensity = data['aiMoodIntensity'];
    if (rawMoodIndex is! num || rawIntensity is! num) return;

    final confidence = ((data['confidence'] as num?)?.toDouble() ?? 0)
        .clamp(0.0, 1.0)
        .toDouble();
    final rank = ((data['stressRank'] as String?) ?? '').trim().toLowerCase();
    final hasAdminResolution =
        (data['resolvedWarningAt'] is Timestamp) ||
        ((data['resolvedWarningSignature'] as String?) ?? '').isNotEmpty;
    final shouldApply =
        confidence > 0 ||
        hasAdminResolution ||
        rank == 'pending' ||
        rank.isEmpty;
    if (!shouldApply) return;

    final moodIndex = rawMoodIndex.toInt().clamp(0, moods.length - 1);
    final intensity = rawIntensity.toDouble().clamp(0.0, 1.0);
    final updatedAt = data['aiMoodStatusUpdatedAt'];
    final updateKey = [
      moodIndex,
      intensity.toStringAsFixed(3),
      if (updatedAt is Timestamp) updatedAt.millisecondsSinceEpoch,
    ].join(':');

    _appData!.updateMoodData(moodIndex: moodIndex, moodIntensity: intensity);

    if (_lastAppliedExternalMoodKey == updateKey) return;
    _lastAppliedExternalMoodKey = updateKey;
    unawaited(_persistExternalMoodAdjustment(moodIndex, intensity));
  }

  // ================= UPDATE MOOD =================

  void updateMood(int moodIndex) {
    if (_appData == null) return;
    _userEditedTodayMood = true;

    _appData!.updateMoodData(
      moodIndex: moodIndex,
      moodIntensity: _appData!.moodIntensity,
    );

    _autoSaveMood();
  }

  // ================= UPDATE INTENSITY =================

  void updateIntensity(double value) {
    if (_appData == null) return;
    _userEditedTodayMood = true;

    _appData!.updateMoodData(
      moodIndex: _appData!.selectedMood,
      moodIntensity: value,
    );

    _autoSaveMood(overrideIntensity: value);
  }

  Future<void> saveMoodNow(AppData appData) async {
    _appData = appData;
    _debounce?.cancel();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final moodIndex = appData.selectedMood;
    final intensity = appData.moodIntensity;

    appData.updateMoodData(moodIndex: moodIndex, moodIntensity: intensity);

    await _cacheMood(
      uid: user.uid,
      dateKey: _todayKey(),
      moodIndex: moodIndex,
      intensity: intensity,
      source: 'manual',
    );
    _pendingMoodIndex = null;
    _pendingMoodIntensity = null;
    await _writeMood(
      moodIndex: moodIndex,
      intensity: intensity,
      source: 'manual',
      updateStreaks: true,
    );
    _scheduleMoodWellnessSignalRefresh();
  }

  Future<void> _writeMood({
    required int moodIndex,
    required double intensity,
    required String source,
    required bool updateStreaks,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = _todayKey();
    await _cacheMood(
      uid: user.uid,
      dateKey: today,
      moodIndex: moodIndex,
      intensity: intensity,
      source: source,
    );
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mood')
        .doc(today)
        .set({
          'mood_index': moodIndex,
          'intensity': intensity,
          'source': source,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    if (!updateStreaks || _appData == null) return;

    final appData = _appData!;
    final updatedMoodData = Map<String, int?>.from(appData.streakMoodData);
    updatedMoodData[today] = moodIndex;
    StreakService.refreshMoodStreak(appData, updatedMoodData);
    await LeaderboardService.publishCurrentUserSummary(
      todaySteps: appData.stepsToday,
    );
  }

  Future<void> applyJournalMood(String journalText) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final result = await GenkitStressAiService.analyzeJournalMood(journalText);
    final today = _todayKey();

    _appData?.updateMoodData(
      moodIndex: result.moodIndex,
      moodIntensity: result.moodIntensity,
    );

    await _cacheMood(
      uid: user.uid,
      dateKey: today,
      moodIndex: result.moodIndex,
      intensity: result.moodIntensity,
      source: 'journal_ai',
    );
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mood')
        .doc(today)
        .set({
          'mood_index': result.moodIndex,
          'intensity': result.moodIntensity,
          'source': result.source,
          'aiCriteria': result.criteria,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    if (_appData != null) {
      final updatedMoodData = Map<String, int?>.from(_appData!.streakMoodData);
      updatedMoodData[today] = result.moodIndex;
      StreakService.refreshMoodStreak(_appData!, updatedMoodData);
      await LeaderboardService.publishCurrentUserSummary(
        todaySteps: _appData!.stepsToday,
      );
      await WellnessSignalService.publishCurrentUserSignals(force: true);
    }
  }

  Future<void> _persistExternalMoodAdjustment(
    int moodIndex,
    double intensity,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = _todayKey();
    try {
      await _cacheMood(
        uid: user.uid,
        dateKey: today,
        moodIndex: moodIndex,
        intensity: intensity,
        source: 'external_ai',
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mood')
          .doc(today)
          .set({
            'mood_index': moodIndex,
            'intensity': intensity,
            'source': 'admin_monitoring_ai',
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (_appData != null) {
        final updatedMoodData = Map<String, int?>.from(
          _appData!.streakMoodData,
        );
        updatedMoodData[today] = moodIndex;
        StreakService.refreshMoodStreak(_appData!, updatedMoodData);
        await LeaderboardService.publishCurrentUserSummary(
          todaySteps: _appData!.stepsToday,
        );
      }
    } catch (error) {
      debugPrint('External mood adjustment save failed: $error');
    }
  }

  // ================= AUTO SAVE =================

  void _autoSaveMood({double? overrideIntensity}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _appData == null) return;

    _debounce?.cancel();

    _pendingMoodIndex = _appData!.selectedMood;
    _pendingMoodIntensity = overrideIntensity ?? _appData!.moodIntensity;
    unawaited(
      _cacheMood(
        uid: user.uid,
        dateKey: _todayKey(),
        moodIndex: _pendingMoodIndex!,
        intensity: _pendingMoodIntensity!,
        source: 'manual',
      ),
    );

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        await flushPendingSave();
      } catch (error) {
        debugPrint('Mood autosave failed: $error');
      }
      _scheduleMoodWellnessSignalRefresh();
    });
  }

  void _scheduleMoodWellnessSignalRefresh() {
    _wellnessPublishDebounce?.cancel();
    _wellnessPublishDebounce = Timer(const Duration(seconds: 6), () {
      unawaited(_publishMoodWellnessSignalRefresh());
    });
  }

  Future<void> _publishMoodWellnessSignalRefresh() async {
    try {
      await WellnessSignalService.publishCurrentUserSignals(force: true);
    } catch (error) {
      debugPrint('Mood wellness signal refresh failed: $error');
    }
  }

  // ================= INSIGHT =================

  String getMoodInsight() {
    if (_appData == null) return "";

    final mood = _appData!.selectedMood;
    final intensity = _appData!.moodIntensity;

    if (mood >= 2 && intensity > 0.7) {
      return "You're feeling amazing today - great energy!";
    } else if (mood == 0 && intensity > 0.7) {
      return "Tough day? Consider taking a short break.";
    } else {
      return "You're doing okay. Stay balanced.";
    }
  }
}

class _CachedMood {
  const _CachedMood({
    required this.moodIndex,
    required this.intensity,
    required this.updatedAt,
    required this.source,
  });

  final int moodIndex;
  final double intensity;
  final DateTime updatedAt;
  final String source;
}
