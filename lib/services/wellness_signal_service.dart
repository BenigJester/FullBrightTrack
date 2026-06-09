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

  static const _rawAiStepDays = 14;
  static const _rawAiMoodDays = 14;
  static const _rawAiJournalLimit = 5;
  static const _rawAiTaskLimit = 20;
  static const _rawAiJournalTextLimit = 700;
  static const _rawAiTaskTitleLimit = 140;
  static const _publishCooldown = Duration(seconds: 45);

  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static Future<void>? _inFlightPublish;
  static DateTime? _lastPublishStartedAt;

  static Future<void> publishCurrentUserSignals({bool force = false}) async {
    final now = DateTime.now();
    if (_inFlightPublish != null && !force) return _inFlightPublish!;
    final lastStarted = _lastPublishStartedAt;
    if (!force &&
        lastStarted != null &&
        now.difference(lastStarted) < _publishCooldown) {
      return;
    }
    if (_inFlightPublish != null) {
      await _inFlightPublish;
    }

    _lastPublishStartedAt = now;
    _inFlightPublish = _publishCurrentUserSignalsNow().whenComplete(() {
      _inFlightPublish = null;
    });
    return _inFlightPublish!;
  }

  static Future<void> _publishCurrentUserSignalsNow() async {
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
    final resolvedWarningJournals = <Map<String, dynamic>>[];
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
      final warningSummary =
          _warningSummaryFromStoredJournal(doc.data()) ??
          JournalWarningService.analyze(text);
      if (warningSummary.findings.isEmpty) continue;

      final signature =
          '${doc.id}:${warningSummary.signatures.take(3).join('|')}';
      if (resolvedSignatures.contains(signature)) {
        resolvedWarningJournals.add({
          'id': doc.id,
          'signature': signature,
          'severityBeforeResolution': warningSummary.severity.name,
          'resolvedByAdmin': true,
          'supportResolutionStatus':
              previousMonitoringData['supportResolutionStatus'] ??
              'support_provided',
          'supportResolutionNote':
              previousMonitoringData['supportResolutionNote'] ??
              'Admin verified this warning after support was provided.',
          'resolvedAt': _timestampText(
            previousMonitoringData['resolvedWarningAt'],
          ),
          'createdAt': _timestampText(doc.data()['created_at']) ?? '',
          'text': '',
        });
        continue;
      }

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
    final hasSupportResolution =
        resolvedWarningJournals.isNotEmpty ||
        resolvedSignatures.isNotEmpty ||
        (previousMonitoringData['supportResolutionStatus'] as String? ?? '')
            .isNotEmpty;
    final adminResolutionContext = {
      'hasResolvedWarning': hasSupportResolution,
      'status': hasSupportResolution
          ? (previousMonitoringData['supportResolutionStatus'] ??
                'support_provided')
          : 'none',
      'note': hasSupportResolution
          ? (previousMonitoringData['supportResolutionNote'] ??
                'Admin verified a previous warning after support was provided.')
          : '',
      'resolvedWarningSignatures': resolvedSignatures.toList(),
      'resolvedWarningJournals': resolvedWarningJournals,
      'activeWarningCount': warningJournals.length,
      'activeWarningSeverity': effectiveWarningSeverity.name,
    };

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
      adminResolutionContext: adminResolutionContext,
    );
    final analyzedResult = hasRawAiConsent
        ? await GenkitStressAiService.analyze(
            input: input,
            rawData: rawData,
            warningSnippets: effectiveWarningSnippets,
            journalWarningWeight: effectiveWarningWeight,
            journalWarningSeverity: effectiveWarningSeverity.name,
            adminResolutionContext: adminResolutionContext,
          )
        : LocalStressModelService.analyze(input);
    final result = _resultForStorage(analyzedResult, previousMonitoringData);
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
      'supportResolutionStatus': adminResolutionContext['status'] == 'none'
          ? FieldValue.delete()
          : adminResolutionContext['status'],
      'supportResolutionNote': adminResolutionContext['note'] == ''
          ? FieldValue.delete()
          : adminResolutionContext['note'],
      'resolvedWarningJournals': resolvedWarningJournals,
      'stressScore': result.score,
      'stressRank': result.rank,
      'confidence': result.confidence,
      'modelVersion': result.modelVersion,
      'rationale': result.rationale,
      'aiMoodStatus': _moodStatusFor(result),
      'aiMoodStatusUpdatedAt': FieldValue.serverTimestamp(),
      'stressHistory': stressHistory,
      'source':
          result.modelVersion == LocalStressModelService.modelVersion ||
              result.modelVersion.startsWith('server-local-fallback')
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

  static StressModelResult _resultForStorage(
    StressModelResult analyzedResult,
    Map<String, dynamic> previousMonitoringData,
  ) {
    if (!_isTemporaryBackendFallback(analyzedResult)) {
      return analyzedResult;
    }

    final previousScore = (previousMonitoringData['stressScore'] as num?)
        ?.toDouble();
    final previousRank = previousMonitoringData['stressRank'] as String?;
    final previousConfidence = (previousMonitoringData['confidence'] as num?)
        ?.toDouble();
    final previousModelVersion =
        previousMonitoringData['modelVersion'] as String?;
    if (previousScore == null ||
        previousRank == null ||
        previousConfidence == null ||
        previousModelVersion == null ||
        previousModelVersion.startsWith('server-local-fallback') ||
        previousModelVersion == LocalStressModelService.modelVersion) {
      return analyzedResult;
    }

    return StressModelResult(
      score: previousScore.clamp(0, 100).toDouble(),
      rank: previousRank,
      confidence: previousConfidence.clamp(0, 1).toDouble(),
      modelVersion: '$previousModelVersion+preserved-during-cooldown',
      rationale:
          (previousMonitoringData['rationale'] as List?)
              ?.whereType<String>()
              .take(3)
              .toList() ??
          analyzedResult.rationale,
    );
  }

  static bool _isTemporaryBackendFallback(StressModelResult result) {
    return result.modelVersion.startsWith('server-local-fallback');
  }

  static JournalWarningSeverity _maxSeverity(
    JournalWarningSeverity current,
    JournalWarningSeverity next,
  ) {
    return next.index > current.index ? next : current;
  }

  static JournalWarningSummary? _warningSummaryFromStoredJournal(
    Map<String, dynamic> data,
  ) {
    final rawFindings = data['warningFindings'];
    if (rawFindings is List && rawFindings.isNotEmpty) {
      final findings = rawFindings
          .whereType<Map>()
          .map((item) {
            final severity = _severityFromName(item['severity'] as String?);
            if (severity == JournalWarningSeverity.none) return null;
            final matchedTerms =
                (item['matchedTerms'] as List?)?.whereType<String>().toList() ??
                [
                  if ((item['snippet'] as String? ?? '').trim().isNotEmpty)
                    (item['snippet'] as String).trim(),
                  severity.label.toLowerCase(),
                ];
            return JournalWarningFinding(
              snippet: (item['snippet'] as String?) ?? '',
              severity: severity,
              weight:
                  ((item['weight'] as num?)?.toDouble() ??
                          _defaultWarningWeight(severity))
                      .clamp(0.0, 1.0)
                      .toDouble(),
              matchedTerms: matchedTerms,
            );
          })
          .whereType<JournalWarningFinding>()
          .toList();
      if (findings.isNotEmpty) {
        return JournalWarningSummary(findings: findings);
      }
    }

    final severity = _severityFromName(
      data['journalWarningSeverity'] as String?,
    );
    final weight =
        ((data['journalWarningWeight'] as num?)?.toDouble() ??
                _defaultWarningWeight(severity))
            .clamp(0.0, 1.0)
            .toDouble();
    if (severity == JournalWarningSeverity.none || weight <= 0) return null;

    final snippets =
        (data['warningSnippets'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    return JournalWarningSummary(
      findings: [
        JournalWarningFinding(
          snippet:
              severity == JournalWarningSeverity.critical && snippets.isNotEmpty
              ? snippets.first
              : '',
          severity: severity,
          weight: weight,
          matchedTerms: snippets.isNotEmpty
              ? snippets
              : [severity.label.toLowerCase()],
        ),
      ],
    );
  }

  static JournalWarningSeverity _severityFromName(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'critical':
        return JournalWarningSeverity.critical;
      case 'elevated':
        return JournalWarningSeverity.elevated;
      case 'stress':
        return JournalWarningSeverity.stress;
      default:
        return JournalWarningSeverity.none;
    }
  }

  static double _defaultWarningWeight(JournalWarningSeverity severity) {
    switch (severity) {
      case JournalWarningSeverity.critical:
        return 1.0;
      case JournalWarningSeverity.elevated:
        return 0.65;
      case JournalWarningSeverity.stress:
        return 0.3;
      case JournalWarningSeverity.none:
        return 0;
    }
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
    required Map<String, dynamic> adminResolutionContext,
  }) {
    return {
      'period': {
        'days': dateKeys.length,
        'startDate': dateKeys.first,
        'endDate': dateKeys.last,
        'rawDetailNote':
            'Raw details are compacted to recent records to stay within free model token limits. Numeric baseline still uses the full query window.',
      },
      'steps': _takeLast(stepsSnapshot.docs, _rawAiStepDays).map((doc) {
        final data = doc.data();
        return {
          'date': doc.id,
          'steps': data['steps'],
          'baseline': data['baseline'],
          'updatedAt': _timestampText(data['updatedAt']),
        };
      }).toList(),
      'moods': _takeLast(moodSnapshot.docs, _rawAiMoodDays).map((doc) {
        final data = doc.data();
        return {
          'date': doc.id,
          'moodIndex': data['mood_index'],
          'intensity': data['intensity'],
          'updatedAt': _timestampText(data['updated_at']),
        };
      }).toList(),
      'journals': journalSnapshot.docs.take(_rawAiJournalLimit).map((doc) {
        final data = doc.data();
        final resolvedJournal =
            (adminResolutionContext['resolvedWarningJournals'] as List?)
                ?.whereType<Map>()
                .where((item) => item['id'] == doc.id)
                .firstOrNull;
        return {
          'id': doc.id,
          'text': resolvedJournal == null
              ? _truncateForAi(data['text'], _rawAiJournalTextLimit)
              : '',
          'tag': _truncateForAi(data['tag'], 80),
          'prompt': _truncateForAi(data['prompt'], 180),
          'createdAt': _timestampText(data['created_at']),
          'adminResolution': resolvedJournal == null
              ? null
              : {
                  'resolvedByAdmin': true,
                  'status': resolvedJournal['supportResolutionStatus'],
                  'note': _truncateForAi(
                    resolvedJournal['supportResolutionNote'],
                    220,
                  ),
                  'resolvedAt': resolvedJournal['resolvedAt'],
                  'instruction':
                      'This journal warning was already verified by an admin after support was provided or as a false positive. Treat it as resolved historical context, not an active unresolved warning.',
                },
          'warningSnippets': resolvedJournal == null
              ? data['warningSnippets']
              : const [],
          'warningFindings': resolvedJournal == null
              ? data['warningFindings']
              : const [],
          'journalWarningWeight': resolvedJournal == null
              ? data['journalWarningWeight']
              : 0,
          'journalWarningSeverity': resolvedJournal == null
              ? data['journalWarningSeverity']
              : 'resolved',
        };
      }).toList(),
      'tasks': _compactTasksForAi(taskSnapshot.docs),
      'latestWarning': {
        'snippets': warningSnippets,
        'findings': warningFindings.take(3).toList(),
        'weight': warningWeight,
        'severity': warningSeverity,
      },
      'adminResolutionContext': _compactResolutionContext(
        adminResolutionContext,
      ),
    };
  }

  static List<Map<String, dynamic>> _compactTasksForAi(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = [...docs];
    sorted.sort((a, b) {
      final aCreated = a.data()['createdAt'];
      final bCreated = b.data()['createdAt'];
      final aTime = aCreated is Timestamp
          ? aCreated.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = bCreated is Timestamp
          ? bCreated.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return sorted.take(_rawAiTaskLimit).map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'title': _truncateForAi(data['title'], _rawAiTaskTitleLimit),
        'isCompleted': data['isCompleted'],
        'deadline': _timestampText(data['deadline']),
        'createdAt': _timestampText(data['createdAt']),
      };
    }).toList();
  }

  static Map<String, dynamic> _compactResolutionContext(
    Map<String, dynamic> context,
  ) {
    final resolvedJournals =
        (context['resolvedWarningJournals'] as List?)
            ?.whereType<Map>()
            .take(3)
            .map(
              (item) => {
                'id': item['id'],
                'signature': item['signature'],
                'severityBeforeResolution': item['severityBeforeResolution'],
                'resolvedByAdmin': true,
                'status': item['supportResolutionStatus'],
                'resolvedAt': item['resolvedAt'],
              },
            )
            .toList() ??
        const [];

    return {
      'hasResolvedWarning': context['hasResolvedWarning'] == true,
      'status': context['status'],
      'note': _truncateForAi(context['note'], 220),
      'resolvedWarningSignatures':
          (context['resolvedWarningSignatures'] as List?)
              ?.whereType<String>()
              .take(5)
              .toList() ??
          const [],
      'resolvedWarningJournals': resolvedJournals,
      'activeWarningCount': context['activeWarningCount'],
      'activeWarningSeverity': context['activeWarningSeverity'],
    };
  }

  static String _truncateForAi(Object? value, int maxLength) {
    final text = (value ?? '').toString().trim();
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength).trim()}...';
  }

  static List<T> _takeLast<T>(List<T> values, int count) {
    if (values.length <= count) return values;
    return values.sublist(values.length - count);
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
