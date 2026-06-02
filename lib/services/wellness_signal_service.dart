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
    final taskSnapshot = await userRef.collection('tasks').limit(60).get();

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
      final isCompleted = data['isCompleted'] == true;
      if (isCompleted) {
        completedTasks++;
      } else if (deadline is! Timestamp) {
        activeTasks++;
      } else if (deadline.toDate().isBefore(now)) {
        overdueTasks++;
      } else {
        activeTasks++;
      }
    }

    final profileData = profile.data() ?? <String, dynamic>{};
    final hasRawAiConsent = profileData['rawAiDataConsent'] == true;

    var warningSnippets = <String>[];
    var warningFindings = <Map<String, dynamic>>[];
    final warningJournals = <Map<String, dynamic>>[];
    var warningSignature = '';
    var warningJournalId = '';
    var warningJournalText = '';
    var warningJournalCreatedAt = '';
    var journalWarningWeight = 0.0;
    var journalWarningSeverity = JournalWarningSeverity.none;
    final monitoringRef = _firestore
        .collection('admin_monitoring')
        .doc(user.uid);
    final previousMonitoringData = await _readMonitoringDataIfAllowed(
      monitoringRef,
    );
    final resolvedSignatures = <String>{
      if ((previousMonitoringData['resolvedWarningSignature'] as String? ?? '')
          .isNotEmpty)
        previousMonitoringData['resolvedWarningSignature'] as String,
      if (previousMonitoringData['resolvedWarningSignatures'] is List)
        ...(previousMonitoringData['resolvedWarningSignatures'] as List)
            .whereType<String>(),
    };

    for (final doc in journalSnapshot.docs) {
      final text = (doc.data()['text'] as String?) ?? '';
      final warningSummary = hasRawAiConsent
          ? await GenkitStressAiService.analyzeJournalWarning(text)
          : JournalWarningService.analyze(text);
      if (warningSummary.findings.isEmpty) continue;

      final signature =
          '${doc.id}:${warningSummary.signatures.take(3).join('|')}';
      if (resolvedSignatures.contains(signature)) continue;

      final snippets = warningSummary.snippets;
      final findings = warningSummary.toJsonList();
      warningJournals.add({
        'id': doc.id,
        'signature': signature,
        'snippets': snippets,
        'findings': findings,
        'severity': warningSummary.severity.name,
        'weight': warningSummary.weight,
        'createdAt': _timestampText(doc.data()['created_at']) ?? '',
        'text': hasRawAiConsent ? text : '',
      });

      warningSnippets = [...warningSnippets, ...snippets].take(5).toList();
      warningFindings = [...warningFindings, ...findings].take(5).toList();
      if (warningSignature.isEmpty) {
        warningSignature = signature;
        warningJournalId = doc.id;
        warningJournalText = text;
        warningJournalCreatedAt =
            _timestampText(doc.data()['created_at']) ?? '';
      }
      journalWarningWeight = max(journalWarningWeight, warningSummary.weight);
      journalWarningSeverity = _maxSeverity(
        journalWarningSeverity,
        warningSummary.severity,
      );
      if (warningJournals.length >= 5) break;
    }
    final effectiveWarningSnippets = warningSnippets;
    final effectiveWarningFindings = warningFindings;
    final effectiveWarningWeight = journalWarningWeight;
    final effectiveWarningSeverity = journalWarningSeverity;

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
    final rawData = _rawAiPayload(
      dateKeys: dateKeys,
      stepsSnapshot: stepsSnapshot,
      moodSnapshot: moodSnapshot,
      journalSnapshot: journalSnapshot,
      taskSnapshot: taskSnapshot,
      warningSnippets: effectiveWarningSnippets,
      warningFindings: effectiveWarningFindings,
      warningWeight: effectiveWarningWeight,
      warningSeverity: effectiveWarningSeverity.name,
    );
    final result = hasRawAiConsent
        ? await GenkitStressAiService.analyze(
            input: input,
            rawData: rawData,
            warningSnippets: effectiveWarningSnippets,
            journalWarningWeight: effectiveWarningWeight,
            journalWarningSeverity: effectiveWarningSeverity.name,
          )
        : LocalStressModelService.analyze(input);
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
      'warningJournals': warningJournals,
      'warningJournalId': warningJournalId,
      'warningJournalText': !hasRawAiConsent ? '' : warningJournalText,
      'warningJournalCreatedAt': warningJournalCreatedAt,
      'journalWarningWeight': effectiveWarningWeight,
      'journalWarningSeverity': effectiveWarningSeverity.name,
      'hasDangerWarning':
          effectiveWarningSeverity == JournalWarningSeverity.critical,
      'stressScore': result.score,
      'stressRank': result.rank,
      'confidence': result.confidence,
      'modelVersion': result.modelVersion,
      'rationale': result.rationale,
      'aiMoodStatus': _moodStatusFor(result),
      'aiMoodStatusUpdatedAt': FieldValue.serverTimestamp(),
      'stressHistory': stressHistory,
      'source': result.modelVersion == LocalStressModelService.modelVersion
          ? 'local_fallback'
          : 'ai_raw_payload',
      'rawAiDataConsent': hasRawAiConsent,
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

  static JournalWarningSeverity _maxSeverity(
    JournalWarningSeverity current,
    JournalWarningSeverity next,
  ) {
    return next.index > current.index ? next : current;
  }

  static Map<String, dynamic> _rawAiPayload({
    required List<String> dateKeys,
    required QuerySnapshot<Map<String, dynamic>> stepsSnapshot,
    required QuerySnapshot<Map<String, dynamic>> moodSnapshot,
    required QuerySnapshot<Map<String, dynamic>> journalSnapshot,
    required QuerySnapshot<Map<String, dynamic>> taskSnapshot,
    required List<String> warningSnippets,
    required List<Map<String, dynamic>> warningFindings,
    required double warningWeight,
    required String warningSeverity,
  }) {
    return {
      'period': {
        'days': dateKeys.length,
        'startDate': dateKeys.first,
        'endDate': dateKeys.last,
      },
      'steps': stepsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'date': doc.id,
          'steps': data['steps'],
          'baseline': data['baseline'],
          'updatedAt': _timestampText(data['updatedAt']),
        };
      }).toList(),
      'moods': moodSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'date': doc.id,
          'moodIndex': data['mood_index'],
          'intensity': data['intensity'],
          'updatedAt': _timestampText(data['updated_at']),
        };
      }).toList(),
      'journals': journalSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'text': data['text'],
          'tag': data['tag'],
          'prompt': data['prompt'],
          'createdAt': _timestampText(data['created_at']),
          'warningSnippets': data['warningSnippets'],
          'warningFindings': data['warningFindings'],
          'journalWarningWeight': data['journalWarningWeight'],
          'journalWarningSeverity': data['journalWarningSeverity'],
        };
      }).toList(),
      'tasks': taskSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'],
          'isCompleted': data['isCompleted'],
          'deadline': _timestampText(data['deadline']),
          'createdAt': _timestampText(data['createdAt']),
        };
      }).toList(),
      'latestWarning': {
        'snippets': warningSnippets,
        'findings': warningFindings,
        'weight': warningWeight,
        'severity': warningSeverity,
      },
    };
  }

  static String? _timestampText(Object? value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    return value?.toString();
  }

  static String _moodStatusFor(StressModelResult result) {
    switch (result.rank) {
      case 'High':
        return 'Needs urgent support';
      case 'Elevated':
        return 'Needs closer check-in';
      case 'Moderate':
        return 'Mixed but manageable';
      default:
        return 'Stable and balanced';
    }
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
