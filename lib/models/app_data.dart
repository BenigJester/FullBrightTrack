import 'package:flutter/foundation.dart';

class AppData extends ChangeNotifier {
  // ================= HOME =================

  Map<String, String>? dailyQuote;
  int stepsToday = 0;
  int moodIndex = -1;
  int currentStreak = 0;
  double trendPercent = 0;

  bool isLoading = false;

  // ================= STEPS =================

  double calories = 0;
  double distance = 0;
  String debugText = "Waiting...";

  // ================= ENGINE =================

  int baseline = 0;
  int initialSteps = 0;
  int lastRawSteps = 0;

  bool baselineSet = false;
  bool ready = false;

  String currentDay = "";

  // ================= GOALS =================

  int stepGoal = 4000;
  int calorieGoal = 300;

  // ================= HEALTH INSIGHTS =================

  int longestStreak = 0;

  String trend = "stable";
  double trendPercentSteps = 0.0;
  String trendLabel = "";

  List<String> insights = [];

  // ================ MOOD TAB ====================

  int selectedMood = 1;
  double moodIntensity = 0.5;

  // ================= STREAK TAB =================

  Map<String, int> streakStepsData = {};
  Map<String, int?> streakMoodData = {};

  int moodCurrentStreak = 0;
  int moodLongestStreak = 0;

  String trendType = "stable";
  String trendLabelStreak = "No activity";
  double streakTrendPercent = 0.0;

  double consistencyPercent = 0;

  // =================== JOURNAL SCREEN =======================

  List<Map<String, dynamic>> journals = [];

  bool journalLoading = false;

  // =========================================================
  // HOME UPDATE
  // =========================================================

  void updateHometabData({
    required Map<String, String>? quote,
    required int steps,
    required int mood,
    required int streak,
    required double trend,
  }) {
    dailyQuote = quote;
    stepsToday = steps;
    moodIndex = mood;
    currentStreak = streak;
    trendPercent = trend;

    notifyListeners();
  }

  // =========================================================
  // STEPS UPDATE (FIXED)
  // =========================================================

  void updateStepsData({
    required int steps,
    required double caloriesValue,
    required double distanceValue,
    required String debug,

    required int baseline,
    required int initialSteps,
    required int lastRawSteps,
    required bool baselineSet,
    required String currentDay,
    required bool ready,

    required int currentStreak,
    required int longestStreak,
    required String trend,
    required double trendPercent,
    required String trendLabel,
    required List<String> insights,
  }) {
    // ================= LIVE VALUES =================
    stepsToday = steps;
    calories = caloriesValue;
    distance = distanceValue;
    debugText = debug;

    // ================= ENGINE =================
    this.baseline = baseline;
    this.initialSteps = initialSteps;
    this.lastRawSteps = lastRawSteps;
    this.baselineSet = baselineSet;
    this.currentDay = currentDay;
    this.ready = ready;

    // ================= INSIGHTS =================
    this.currentStreak = currentStreak;
    this.longestStreak = longestStreak;
    this.trend = trend;
    this.trendPercent = trendPercent;
    this.trendLabel = trendLabel;
    this.insights = insights;

    notifyListeners();
  }

  // =========================================================
  // MOOD UPDATE
  // =========================================================

  void updateMoodData({required int moodIndex, required double moodIntensity}) {
    selectedMood = moodIndex;
    this.moodIntensity = moodIntensity;
    this.moodIndex = moodIndex;

    notifyListeners();
  }

  // =========================================================
  // MOOD UPDATE
  // =========================================================

  // =========================================================
  // STREAK UPDATE
  // =========================================================

  void updateStreakData({
    required Map<String, int> stepsData,
    required Map<String, int?> moodData,
    required int current,
    required int longest,
    required int moodCurrent,
    required int moodLongest,
    required String trend,
    required String label,
    required double percent,
    required double consistency,
  }) {
    streakStepsData = stepsData;
    streakMoodData = moodData;

    currentStreak = current;
    longestStreak = longest;

    moodCurrentStreak = moodCurrent;
    moodLongestStreak = moodLongest;

    trendType = trend;
    trendLabelStreak = label;
    streakTrendPercent = percent;

    consistencyPercent = consistency;

    notifyListeners();
  }

  void setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  // =========================================================
  // JOURNAL UPDATE
  // =========================================================

  void updateJournalData({
    required List<Map<String, dynamic>> journalList,
    required bool loading,
  }) {
    journals = journalList;
    journalLoading = loading;

    notifyListeners();
  }
}