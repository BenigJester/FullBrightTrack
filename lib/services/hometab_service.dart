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

    final stepDocs = await Future.wait(
      dates.map((date) => stepsRef.doc(date).get()),
    );

    // ================= MAP DATA =================

    final Map<String, int> stepMap = {};

    for (int i = 0; i < dates.length; i++) {
      final data = stepDocs[i].data();

      stepMap[dates[i]] = ((data as Map?)?['steps'] as num?)?.toInt() ?? 0;
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

    double trendPercent;

    if (sumPrev == 0 && sumLast == 0) {
      trendPercent = 0;
    } else if (sumPrev == 0) {
      trendPercent = 100;
    } else {
      trendPercent = ((sumLast - sumPrev) / sumPrev) * 100;
    }

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
}
