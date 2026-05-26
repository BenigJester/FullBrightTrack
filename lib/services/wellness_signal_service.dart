import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'display_name_service.dart';
import 'genkit_stress_ai_service.dart';
import 'journal_warning_service.dart';
import 'local_stress_model_service.dart';

class WellnessSignalService {
  const WellnessSignalService._();

  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static Future<void> publishCurrentUserSignals() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 29));
    final dateKeys = List.generate(30, (index) {
      return _dateKey(start.add(Duration(days: index)));
    });
    final userRef = _firestore.collection('users').doc(user.uid);

    final profile = await userRef.get();
    final stepsSnapshot = await userRef
        .collection('steps')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: dateKeys.first)
        .where(FieldPath.documentId, isLessThanOrEqualTo: dateKeys.last)
        .orderBy(FieldPath.documentId)
        .get();
    final moodSnapshot = await userRef
        .collection('mood')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: dateKeys.first)
        .where(FieldPath.documentId, isLessThanOrEqualTo: dateKeys.last)
        .orderBy(FieldPath.documentId)
        .get();
    final journalSnapshot = await userRef
        .collection('journal')
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('created_at', descending: true)
        .limit(30)
        .get();
    final taskSnapshot = await userRef
        .collection('tasks')
        .where('deadline', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('deadline', descending: true)
        .limit(60)
        .get();

    final totalSteps = stepsSnapshot.docs.fold<int>(
      0,
      (total, doc) => total + ((doc.data()['steps'] as num?)?.toInt() ?? 0),
    );
    final moodValues = moodSnapshot.docs.map((doc) {
      final data = doc.data();
      return _MoodSignal(
        moodIndex: (data['mood_index'] as num?)?.toDouble() ?? 1,
        intensity: (data['intensity'] as num?)?.toDouble() ?? 0.5,
      );
    }).toList();
    final avgMoodIndex = moodValues.isEmpty
        ? 0.0
        : moodValues.map((mood) => mood.moodIndex).reduce((a, b) => a + b) /
              moodValues.length;
    final avgMoodIntensity = moodValues.isEmpty
        ? 0.0
        : moodValues.map((mood) => mood.intensity).reduce((a, b) => a + b) /
              moodValues.length;

    var activeTasks = 0;
    var completedTasks = 0;
    var overdueTasks = 0;
    for (final doc in taskSnapshot.docs) {
      final data = doc.data();
      final deadline = data['deadline'];
      if (deadline is! Timestamp) continue;

      final isCompleted = data['isCompleted'] == true;
      if (isCompleted) {
        completedTasks++;
      } else if (deadline.toDate().isBefore(now)) {
        overdueTasks++;
      } else {
        activeTasks++;
      }
    }

    final warningSnippets = <String>[];
    for (final doc in journalSnapshot.docs) {
      final text = (doc.data()['text'] as String?) ?? '';
      warningSnippets.addAll(
        JournalWarningService.extractWarningSnippets(text),
      );
      if (warningSnippets.length >= 5) break;
    }

    final input = StressModelInput(
      avgMoodIndex: avgMoodIndex,
      avgMoodIntensity: avgMoodIntensity,
      avgDailySteps: totalSteps / max(1, dateKeys.length),
      moodLogCoverage: moodValues.length / max(1, dateKeys.length),
      journalEntryCount: journalSnapshot.docs.length,
      activeTaskCount: activeTasks,
      completedTaskCount: completedTasks,
      overdueTaskCount: overdueTasks,
    );
    final result = await GenkitStressAiService.analyze(
      input: input,
      warningSnippets: warningSnippets,
    );
    final profileData = profile.data() ?? <String, dynamic>{};
    final displayName = DisplayNameService.cleanForDisplay(
      profileData['name'] as String? ?? user.displayName,
      fallback: 'Student',
    );

    await _firestore.collection('admin_monitoring').doc(user.uid).set({
      'uid': user.uid,
      'name': displayName,
      'email': user.email ?? profileData['email'],
      'photoUrl': profileData['photoUrl'] ?? user.photoURL,
      'avgMoodIndex': input.avgMoodIndex,
      'avgMoodIntensity': input.avgMoodIntensity,
      'avgDailySteps': input.avgDailySteps,
      'moodLogCoverage': input.moodLogCoverage,
      'journalEntryCount': input.journalEntryCount,
      'activeTaskCount': input.activeTaskCount,
      'completedTaskCount': input.completedTaskCount,
      'overdueTaskCount': input.overdueTaskCount,
      'warningSnippets': warningSnippets.take(5).toList(),
      'hasDangerWarning': warningSnippets.isNotEmpty,
      'stressScore': result.score,
      'stressRank': result.rank,
      'confidence': result.confidence,
      'modelVersion': result.modelVersion,
      'rationale': result.rationale,
      'source': result.modelVersion == LocalStressModelService.modelVersion
          ? 'local_fallback'
          : 'genkit_minimized_payload',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String _dateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}

class _MoodSignal {
  const _MoodSignal({required this.moodIndex, required this.intensity});

  final double moodIndex;
  final double intensity;
}
