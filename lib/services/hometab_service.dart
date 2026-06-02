import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'quote_service.dart';
import '../models/app_data.dart';

class HomeTabService {
  static const _cachePrefix = 'home_tab_cache_';

  static String _format(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static String _todayKey() => _format(DateTime.now());

  static Future<bool> loadCached(AppData appData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix${user.uid}');
    if (raw == null || raw.isEmpty) return false;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;

      final quoteData = decoded['quote'];
      final quote = quoteData is Map
          ? quoteData.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : null;

      final cachedMood = (decoded['mood'] as num?)?.toInt() ?? -1;
      final visibleMood = cachedMood >= 0 ? cachedMood : appData.moodIndex;

      appData.updateHometabData(
        quote: quote,
        steps: (decoded['steps'] as num?)?.toInt() ?? 0,
        mood: visibleMood,
        streak: (decoded['streak'] as num?)?.toInt() ?? 0,
        trend: (decoded['trend'] as num?)?.toDouble() ?? 0,
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> preload(AppData appData) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final now = DateTime.now();

    final stepsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('steps');

    final moodRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mood');

    // ================= LOAD PARALLEL =================

    final today = _todayKey();

    final quote = await QuoteService.getDailyQuote();
    final stepsDoc = await _safeGet(stepsRef.doc(today));
    final moodDoc = await _safeGet(moodRef.doc(today));

    // ================= QUOTE =================

    try {
      appData.dailyQuote = quote;
    } catch (_) {
      appData.dailyQuote = {
        "quote": "Stay consistent. Small steps matter.",
        "author": "System",
      };
    }

    // ================= TODAY DATA =================

    final stepsToday = (stepsDoc?.data()?['steps'] as num?)?.toInt() ?? 0;

    final savedMoodIndex = moodDoc?.data()?['mood_index'];
    final moodIndex = savedMoodIndex is num
        ? savedMoodIndex.toInt()
        : appData.moodIndex;

    // ================= LOAD 30 DAYS PARALLEL =================

    final dates = List.generate(
      30,
      (i) => _format(now.subtract(Duration(days: i))),
    );

    // ================= MAP DATA =================

    final stepMap = {for (final date in dates) date: 0};

    try {
      final stepSnapshot = await stepsRef
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: dates.last)
          .where(FieldPath.documentId, isLessThanOrEqualTo: dates.first)
          .orderBy(FieldPath.documentId)
          .get();

      for (final doc in stepSnapshot.docs) {
        stepMap[doc.id] = (doc.data()['steps'] as num?)?.toInt() ?? 0;
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('Home step trend skipped: permission-denied');
      } else {
        rethrow;
      }
    }

    // ================= TREND =================

    int sumLast = 0;

    int sumPrev = 0;

    for (int i = 0; i < 14; i++) {
      final key = dates[i];

      final steps = stepMap[key] ?? 0;

      if (i < 7) {
        sumLast += steps;
      } else {
        sumPrev += steps;
      }
    }

    final trendPercent = _calculateTrendPercent(
      sumLast: sumLast,
      sumPrev: sumPrev,
      goal: appData.stepGoal,
    );

    // ================= STREAK =================

    int streak = 0;

    for (int i = 0; i < 30; i++) {
      final key = dates[i];

      final steps = stepMap[key] ?? 0;

      if (steps >= appData.stepGoal) {
        streak++;
      } else {
        break;
      }
    }

    // ================= UPDATE APPDATA =================

    appData.updateHometabData(
      quote: appData.dailyQuote,
      steps: stepsToday,
      mood: moodIndex,
      streak: streak,
      trend: trendPercent,
    );

    await _cacheHomeData(
      uid: user.uid,
      quote: appData.dailyQuote,
      steps: stepsToday,
      mood: moodIndex,
      streak: streak,
      trend: trendPercent,
    );
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> _safeGet(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return await ref.get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('Home preload document skipped: permission-denied');
        return null;
      }

      rethrow;
    }
  }

  static Future<void> _cacheHomeData({
    required String uid,
    required Map<String, String>? quote,
    required int steps,
    required int mood,
    required int streak,
    required double trend,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_cachePrefix$uid',
      jsonEncode({
        'quote': quote,
        'steps': steps,
        'mood': mood,
        'streak': streak,
        'trend': trend,
        'cachedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  static double _calculateTrendPercent({
    required int sumLast,
    required int sumPrev,
    required int goal,
  }) {
    if (sumPrev == 0 && sumLast == 0) {
      return 0;
    }

    if (sumPrev == 0 && sumLast > 0) {
      return 100;
    }

    if (sumPrev > 0 && sumLast == 0) {
      return -100;
    }

    final minimumMeaningfulBaseline = goal > 0 ? goal : 1000;

    if (sumPrev < minimumMeaningfulBaseline &&
        sumLast >= minimumMeaningfulBaseline) {
      return 100;
    }

    if (sumPrev < minimumMeaningfulBaseline &&
        sumLast < minimumMeaningfulBaseline) {
      return 0;
    }

    final rawPercent = ((sumLast - sumPrev) / sumPrev) * 100;

    return rawPercent.clamp(-100.0, 100.0).toDouble();
  }
}
