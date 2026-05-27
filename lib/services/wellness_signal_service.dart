import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'display_name_service.dart';
import 'admin_alert_service.dart';
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

    final recordedSteps = stepsSnapshot.docs
        .map((doc) => (doc.data()['steps'] as num?)?.toInt() ?? 0)
        .where((steps) => steps > 0)
        .toList();
    final avgDailySteps = averageRecordedDailySteps(recordedSteps);
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

    var warningSnippets = <String>[];
    var warningFindings = <Map<String, dynamic>>[];
    var warningSignature = '';
    var journalWarningWeight = 0.0;
    var journalWarningSeverity = JournalWarningSeverity.none;
    for (final doc in journalSnapshot.docs) {
      final text = (doc.data()['text'] as String?) ?? '';
      final warningSummary = JournalWarningService.analyze(text);
      if (warningSummary.findings.isEmpty) continue;

      warningSnippets = warningSummary.snippets;
      warningFindings = warningSummary.toJsonList();
      warningSignature =
          '${doc.id}:${warningSummary.signatures.take(3).join('|')}';
      journalWarningWeight = warningSummary.weight;
      journalWarningSeverity = warningSummary.severity;
      break;
    }
    final monitoringRef = _firestore
        .collection('admin_monitoring')
        .doc(user.uid);
    final previousMonitoringData = await _readMonitoringDataIfAllowed(
      monitoringRef,
    );
    final resolvedWarningSignature =
        previousMonitoringData['resolvedWarningSignature'] as String? ?? '';
    final warningResolved =
        warningSignature.isNotEmpty &&
        warningSignature == resolvedWarningSignature;
    final effectiveWarningSnippets = warningResolved
        ? <String>[]
        : warningSnippets;
    final effectiveWarningFindings = warningResolved
        ? <Map<String, dynamic>>[]
        : warningFindings;
    final effectiveWarningWeight = warningResolved ? 0.0 : journalWarningWeight;
    final effectiveWarningSeverity = warningResolved
        ? JournalWarningSeverity.none
        : journalWarningSeverity;

    final input = StressModelInput(
      avgMoodIndex: avgMoodIndex,
      avgMoodIntensity: avgMoodIntensity,
      avgDailySteps: avgDailySteps,
      moodLogCoverage: moodValues.length / max(1, dateKeys.length),
      journalEntryCount: journalSnapshot.docs.length,
      activeTaskCount: activeTasks,
      completedTaskCount: completedTasks,
      overdueTaskCount: overdueTasks,
      journalWarningWeight: effectiveWarningWeight,
    );
    final result = await GenkitStressAiService.analyze(
      input: input,
      warningSnippets: effectiveWarningSnippets,
      journalWarningWeight: effectiveWarningWeight,
      journalWarningSeverity: effectiveWarningSeverity.name,
    );
    final profileData = profile.data() ?? <String, dynamic>{};
    final displayName = DisplayNameService.cleanForDisplay(
      profileData['name'] as String? ?? user.displayName,
      fallback: 'Student',
    );
    final previousHistory = previousMonitoringData['stressHistory'];
    final stressHistory = <String, double>{
      if (previousHistory is Map)
        for (final entry in previousHistory.entries)
          if (dateKeys.contains(entry.key) && entry.value is num)
            entry.key.toString(): (entry.value as num).toDouble(),
      _dateKey(now): result.score,
    };

    await monitoringRef.set({
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
      'warningSnippets': effectiveWarningSnippets.take(5).toList(),
      'warningFindings': effectiveWarningFindings.take(5).toList(),
      'warningSignature': warningSignature,
      'journalWarningWeight': effectiveWarningWeight,
      'journalWarningSeverity': effectiveWarningSeverity.name,
      'hasDangerWarning':
          effectiveWarningSeverity == JournalWarningSeverity.critical,
      'stressScore': result.score,
      'stressRank': result.rank,
      'confidence': result.confidence,
      'modelVersion': result.modelVersion,
      'rationale': result.rationale,
      'stressHistory': stressHistory,
      'source': result.modelVersion == LocalStressModelService.modelVersion
          ? 'local_fallback'
          : 'ai_minimized_payload',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (effectiveWarningSeverity == JournalWarningSeverity.critical) {
      await AdminAlertService.publishCriticalWarningAlert(
        userId: user.uid,
        displayName: displayName,
        warningSignature: warningSignature,
        modelResult: result,
      );
    }
  }

  static String _dateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  static double averageRecordedDailySteps(Iterable<int> recordedSteps) {
    final positiveSteps = recordedSteps.where((steps) => steps > 0).toList();
    if (positiveSteps.isEmpty) return 0;

    final total = positiveSteps.fold<int>(
      0,
      (runningTotal, steps) => runningTotal + steps,
    );
    return total / positiveSteps.length;
  }

  static Future<Map<String, dynamic>> _readMonitoringDataIfAllowed(
    DocumentReference<Map<String, dynamic>> monitoringRef,
  ) async {
    try {
      return (await monitoringRef.get()).data() ?? <String, dynamic>{};
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return <String, dynamic>{};
      }
      rethrow;
    }
  }
}

class _MoodSignal {
  const _MoodSignal({required this.moodIndex, required this.intensity});

  final double moodIndex;
  final double intensity;
}
