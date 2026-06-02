import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
    _debounce?.cancel();
    _wellnessPublishDebounce?.cancel();
    _aiMoodSubscription?.cancel();
    _aiMoodSubscription = null;
  }

  // ================= DATE =================

  String _todayKey() {
    final now = DateTime.now();

    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  // ================= LOAD TODAY MOOD =================

  Future<void> loadTodayMood() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || _appData == null) {
      return;
    }

    final today = _todayKey();
    _userEditedTodayMood = false;

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
        _appData!.updateMoodData(moodIndex: 1, moodIntensity: 0.5);
        return;
      }

      rethrow;
    }

    if (!doc.exists) {
      _appData!.updateMoodData(moodIndex: 1, moodIntensity: 0.5);
      await _applyLatestAiMoodAdjustment();

      return;
    }

    _appData!.updateMoodData(
      moodIndex: doc.data()?['mood_index'] ?? 1,
      moodIntensity: (doc.data()?['intensity'] ?? 0.5).toDouble(),
    );
    await _applyLatestAiMoodAdjustment();
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

    final today = _todayKey();
    final moodIndex = appData.selectedMood;
    final intensity = appData.moodIntensity;

    appData.updateMoodData(moodIndex: moodIndex, moodIntensity: intensity);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mood')
        .doc(today)
        .set({
          'mood_index': moodIndex,
          'intensity': intensity,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    final updatedMoodData = Map<String, int?>.from(appData.streakMoodData);
    updatedMoodData[today] = moodIndex;
    StreakService.refreshMoodStreak(appData, updatedMoodData);
    await LeaderboardService.publishCurrentUserSummary(
      todaySteps: appData.stepsToday,
    );
    _scheduleMoodWellnessSignalRefresh();
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

    final today = _todayKey();

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final moodIndex = _appData!.selectedMood;
      final intensity = overrideIntensity ?? _appData!.moodIntensity;

      // 1. SAVE TO FIRESTORE
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mood')
          .doc(today)
          .set({
            'mood_index': moodIndex,
            'intensity': intensity,
            'updated_at': FieldValue.serverTimestamp(),
          });
      final updatedMoodData = Map<String, int?>.from(_appData!.streakMoodData);

      updatedMoodData[today] = moodIndex;

      StreakService.refreshMoodStreak(_appData!, updatedMoodData);
      await LeaderboardService.publishCurrentUserSummary(
        todaySteps: _appData!.stepsToday,
      );
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
