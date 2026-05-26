import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'quote_service.dart';
import '../models/app_data.dart';

class HomeTabService {
  static String _format(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static String _todayKey() => _format(DateTime.now());

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

    final futures = await Future.wait([
      QuoteService.getDailyQuote(),

      stepsRef.doc(today).get(),

      moodRef.doc(today).get(),
    ]);

    // ================= QUOTE =================

    try {
      appData.dailyQuote = futures[0] as Map<String, String>;
    } catch (_) {
      appData.dailyQuote = {
        "quote": "Stay consistent. Small steps matter.",
        "author": "System",
      };
    }

    // ================= TODAY DATA =================

    final stepsDoc = futures[1] as DocumentSnapshot;

    final moodDoc = futures[2] as DocumentSnapshot;

    final stepsToday = (stepsDoc.data() as Map?)?['steps'] ?? 0;

    final moodIndex = (moodDoc.data() as Map?)?['mood_index'] ?? -1;

    // ================= LOAD 30 DAYS PARALLEL =================

    final dates = List.generate(
      30,
      (i) => _format(now.subtract(Duration(days: i))),
    );

    // ================= MAP DATA =================

    final stepSnapshot = await stepsRef
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: dates.last)
        .where(FieldPath.documentId, isLessThanOrEqualTo: dates.first)
        .orderBy(FieldPath.documentId)
        .get();

    final stepMap = {for (final date in dates) date: 0};

    for (final doc in stepSnapshot.docs) {
      stepMap[doc.id] = (doc.data()['steps'] as num?)?.toInt() ?? 0;
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
