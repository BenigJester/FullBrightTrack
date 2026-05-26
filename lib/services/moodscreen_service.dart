import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'streak_service.dart';
import '../models/app_data.dart';
import 'leaderboard_service.dart';
import 'wellness_signal_service.dart';

class MoodService {
  // ================= SINGLETON =================

  static final MoodService instance = MoodService._internal();

  factory MoodService() => instance;

  MoodService._internal();

  // ================= APP DATA =================

  AppData? _appData;

  // ================= SAVE =================

  Timer? _debounce;

  // ================= MOODS =================

  final moods = ["\u{1F61E}", "\u{1F642}", "\u{1F604}", "\u{1F929}"];

  // ================= INITIALIZE =================

  Future<void> initialize(AppData appData) {
    _appData = appData;

    return loadTodayMood();
  }

  // ================= DISPOSE =================

  void dispose() {
    _debounce?.cancel();
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

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mood')
        .doc(today)
        .get();

    if (!doc.exists) {
      _appData!.updateMoodData(moodIndex: 1, moodIntensity: 0.5);

      return;
    }

    _appData!.updateMoodData(
      moodIndex: doc.data()?['mood_index'] ?? 1,
      moodIntensity: (doc.data()?['intensity'] ?? 0.5).toDouble(),
    );
  }

  // ================= UPDATE MOOD =================

  void updateMood(int moodIndex) {
    if (_appData == null) return;

    _appData!.updateMoodData(
      moodIndex: moodIndex,
      moodIntensity: _appData!.moodIntensity,
    );

    _autoSaveMood();
  }

  // ================= UPDATE INTENSITY =================

  void updateIntensity(double value) {
    if (_appData == null) return;

    _appData!.updateMoodData(
      moodIndex: _appData!.selectedMood,
      moodIntensity: value,
    );

    _autoSaveMood(overrideIntensity: value);
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
      await WellnessSignalService.publishCurrentUserSignals();
    });
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
