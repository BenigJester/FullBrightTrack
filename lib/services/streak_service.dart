import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_data.dart';

class StreakService {
  static const int goal = 4000;

  // ================= PRELOAD =================

  static Future<void> preload(AppData appData) async {
    final results = await Future.wait([
      _getLastNDaysSteps(30),
      _getLastNDaysMood(30),
      _loadOfflineQueue(),
    ]);

    final stepsData = results[0] as Map<String, int>;
    final moodData = results[1] as Map<String, int>;
    final offline = results[2] as List<Map<String, dynamic>>;

    // ================= MERGE OFFLINE =================

    for (final item in offline) {
      if (stepsData.containsKey(item['day'])) {
        stepsData[item['day']] = item['steps'];
      }
    }

    // ================= CALCULATIONS =================

    final streak = _calculateStreaks(stepsData, goal);

    final moodStreak = _calculateMoodStreak(moodData);

    final trend = _calculateTrend(stepsData);

    // ================= CONSISTENCY =================

    final active = stepsData.values.where((s) => s >= goal).length;

    final consistency = stepsData.isEmpty
        ? 0.0
        : (active / stepsData.length) * 100;

    // ================= UPDATE APPDATA =================

    appData.updateStreakData(
      stepsData: stepsData,
      moodData: moodData,

      current: streak["current"]!,
      longest: streak["longest"]!,

      moodCurrent: moodStreak["current"]!,
      moodLongest: moodStreak["longest"]!,

      trend: trend["trend"],
      label: trend["label"],

      percent: trend["percent"],

      consistency: consistency,
    );
  }

  // ================= OFFLINE =================

  static Future<List<Map<String, dynamic>>> _loadOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString('steps_queue');

    if (raw == null) return [];

    final List decoded = jsonDecode(raw);

    return decoded.cast<Map<String, dynamic>>();
  }

  // ================= FETCH STEPS =================

  static Future<Map<String, int>> _getLastNDaysSteps(int days) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return {};

    final now = DateTime.now();

    final start = now.subtract(Duration(days: days - 1));

    final futures = List.generate(days, (i) async {
      final date = start.add(Duration(days: i));

      final key =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('steps')
          .doc(key)
          .get();

      return MapEntry(key, (doc.data()?['steps'] as num?)?.toInt() ?? 0);
    });

    final entries = await Future.wait(futures);

    return Map.fromEntries(entries);
  }

  // ================= FETCH MOOD =================

  static Future<Map<String, int>> _getLastNDaysMood(int days) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return {};

    final now = DateTime.now();

    final start = now.subtract(Duration(days: days - 1));

    final futures = List.generate(days, (i) async {
      final date = start.add(Duration(days: i));

      final key =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mood')
          .doc(key)
          .get();

      return MapEntry(key, (doc.data()?['mood_index'] as num?)?.toInt() ?? 0);
    });

    final entries = await Future.wait(futures);

    return Map.fromEntries(entries);
  }

  // ================= STREAK =================

  static Map<String, int> _calculateStreaks(Map<String, int> data, int goal) {
    final dates = data.keys.toList()..sort();

    int current = 0;
    int longest = 0;
    int temp = 0;

    for (final d in dates) {
      if ((data[d] ?? 0) >= goal) {
        temp++;

        if (temp > longest) {
          longest = temp;
        }
      } else {
        temp = 0;
      }
    }

    for (int i = dates.length - 1; i >= 0; i--) {
      if ((data[dates[i]] ?? 0) >= goal) {
        current++;
      } else {
        break;
      }
    }

    return {"current": current, "longest": longest};
  }

  // ================= MOOD STREAK =================

  static Map<String, int> _calculateMoodStreak(Map<String, int> moodData) {
    final dates = moodData.keys.toList()..sort();

    int current = 0;
    int longest = 0;
    int temp = 0;

    for (final d in dates) {
      final mood = moodData[d] ?? 0;

      if (mood >= 2) {
        temp++;

        if (temp > longest) {
          longest = temp;
        }
      } else {
        temp = 0;
      }
    }

    for (int i = dates.length - 1; i >= 0; i--) {
      if ((moodData[dates[i]] ?? 0) >= 2) {
        current++;
      } else {
        break;
      }
    }

    return {"current": current, "longest": longest};
  }

  // ================= TREND =================

  static Map<String, dynamic> _calculateTrend(Map<String, int> data) {
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

    final percent = ((sumLast - sumPrev) / sumPrev) * 100;

    if (percent > 5) {
      return {"trend": "up", "percent": percent, "label": "Improving"};
    } else if (percent < -5) {
      return {"trend": "down", "percent": percent, "label": "Declining"};
    }

    return {"trend": "stable", "percent": percent, "label": "Stable"};
  }

  // ============================= Refresh Mood Streak ====================

  static void refreshMoodStreak(AppData appData, Map<String, int> moodData) {
    final moodStreak = _calculateMoodStreak(moodData);

    appData.updateStreakData(
      stepsData: appData.streakStepsData,
      moodData: moodData,

      current: appData.currentStreak,
      longest: appData.longestStreak,

      moodCurrent: moodStreak["current"]!,
      moodLongest: moodStreak["longest"]!,

      trend: appData.trendType,
      label: appData.trendLabel,

      percent: appData.streakTrendPercent,

      consistency: appData.consistencyPercent,
    );
  }
}
