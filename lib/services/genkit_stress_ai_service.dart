import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_stress_model_service.dart';
import 'journal_warning_service.dart';

class GenkitStressAiService {
  const GenkitStressAiService._();

  static const _configuredFlowUrl = String.fromEnvironment(
    'GENKIT_STRESS_FLOW_URL',
  );
  static const _debugLocalFlowUrl = String.fromEnvironment(
    'GENKIT_STRESS_DEBUG_URL',
    defaultValue: 'http://10.0.2.2:8080/stress',
  );

  static String get _flowUrl {
    final configured = _configuredFlowUrl.trim();
    if (configured.isNotEmpty) return configured;
    return kReleaseMode ? '' : _debugLocalFlowUrl.trim();
  }

  static bool get isConfigured => _flowUrl.isNotEmpty;

  static Future<StressModelResult> analyze({
    required StressModelInput input,
    required Map<String, dynamic> rawData,
    required List<String> warningSnippets,
    required double journalWarningWeight,
    required String journalWarningSeverity,
    Map<String, dynamic> adminResolutionContext = const {},
  }) async {
    if (!isConfigured) {
      throw const AiServiceException(
        'AI service is not configured. Connect to the backend and try again.',
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse(_flowUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'rawData': rawData,
              'localBaseline': {
                'avgMoodIndex': input.avgMoodIndex,
                'avgMoodIntensity': input.avgMoodIntensity,
                'avgDailySteps': input.avgDailySteps,
                'moodLogCoverage': input.moodLogCoverage,
                'journalEntryCount': input.journalEntryCount,
                'activeTaskCount': input.activeTaskCount,
                'completedTaskCount': input.completedTaskCount,
                'overdueTaskCount': input.overdueTaskCount,
              },
              'warningSnippets': warningSnippets.take(3).toList(),
              'journalWarningWeight': journalWarningWeight.clamp(0, 1),
              'journalWarningSeverity': journalWarningSeverity,
              'adminResolutionContext': adminResolutionContext,
              'instructions':
                  'If adminResolutionContext.hasResolvedWarning is true, treat matching resolved warning journals as historical resolved context after support was provided or after admin marked them false positive, not active unresolved danger. Score high only when fresh unresolved mood, journal, task, or activity signals still show current risk.',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
          'AI service returned ${response.statusCode}. Try again later.',
        );
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final output = data['result'] is Map<String, dynamic>
          ? data['result'] as Map<String, dynamic>
          : data;

      final result = StressModelResult(
        score: ((output['score'] as num?)?.toDouble() ?? 0)
            .clamp(0, 100)
            .toDouble(),
        rank:
            (output['rank'] as String?) ??
            LocalStressModelService.rankForScore(
              (output['score'] as num?)?.toDouble() ?? 0,
            ),
        confidence: ((output['confidence'] as num?)?.toDouble() ?? 0.5)
            .clamp(0, 1)
            .toDouble(),
        modelVersion: (output['modelVersion'] as String?) ?? 'ai-flow',
        rationale:
            (output['rationale'] as List?)
                ?.whereType<String>()
                .take(3)
                .toList() ??
            const ['AI flow result'],
      );
      final fallbackReason = output['fallbackReason'] as String?;
      if (fallbackReason != null && fallbackReason.trim().isNotEmpty) {
        throw AiServiceException(
          'AI service fallback was refused: $fallbackReason.',
        );
      }
      debugPrint('Stress AI backend result: ${result.modelVersion}');
      return result;
    } on AiServiceException {
      rethrow;
    } catch (_) {
      throw const AiServiceException(
        'AI service is unreachable. Check your internet connection and retry.',
      );
    }
  }

  static Future<JournalWarningSummary> analyzeJournalWarning(
    String journalText,
  ) async {
    if (journalText.trim().isEmpty) {
      return const JournalWarningSummary(findings: []);
    }
    if (!isConfigured) {
      throw const AiServiceException(
        'AI journal warning review is not configured.',
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse(_flowUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': 'journal-warning',
              'rawJournalText': journalText,
              'instructions':
                  'Classify safety severity from raw student journal text. Understand English and Philippine languages such as Tagalog, Cebuano, Ilocano, Hiligaynon, Waray, Kapampangan, Pangasinan, Bicolano, and mixed local-English writing. Detect self-harm, threats or harm toward other people, violent intent, coercion, harassment, and explicit unsafe wording. If wording is clearly slang, a harmless joke, quoted media, or not an actual safety concern, return severity none with confidence. Return severity, weight, warningSignalTerm, and confidence.',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
          'AI journal warning review returned ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final output = data['result'] is Map<String, dynamic>
          ? data['result'] as Map<String, dynamic>
          : data;
      final fallbackReason = output['fallbackReason'] as String?;
      if (fallbackReason != null && fallbackReason.trim().isNotEmpty) {
        throw AiServiceException(
          'AI journal warning fallback was refused: $fallbackReason.',
        );
      }
      final severity = ((output['severity'] as String?) ?? 'none')
          .trim()
          .toLowerCase();

      return JournalWarningService.fromAi(
        severity: severity,
        weight: ((output['weight'] as num?)?.toDouble() ?? 0)
            .clamp(0, 1)
            .toDouble(),
        warningSignalTerm: (output['warningSignalTerm'] as String?) ?? '',
      );
    } on AiServiceException {
      rethrow;
    } catch (_) {
      throw const AiServiceException(
        'AI journal warning review is unreachable. Check your internet connection and retry.',
      );
    }
  }

  static Future<JournalMoodResult> analyzeJournalMood(
    String journalText,
  ) async {
    if (journalText.trim().isEmpty) return JournalMoodResult.local(journalText);
    if (!isConfigured) {
      throw const AiServiceException('AI mood review is not configured.');
    }

    try {
      final response = await http
          .post(
            Uri.parse(_flowUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': 'journal-mood',
              'rawJournalText': journalText,
              'instructions':
                  'Read the raw journal and estimate moodIndex 0 sad, 1 low/neutral, 2 okay/positive, 3 energized/very happy/excited/grateful/proud, plus moodIntensity 0.0 to 1.0. Strong happy journals should be allowed to return moodIndex 3. Return criteria.',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
          'AI mood review returned ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final output = data['result'] is Map<String, dynamic>
          ? data['result'] as Map<String, dynamic>
          : data;
      final fallbackReason = output['fallbackReason'] as String?;
      if (fallbackReason != null && fallbackReason.trim().isNotEmpty) {
        throw AiServiceException(
          'AI mood fallback was refused: $fallbackReason.',
        );
      }

      return JournalMoodResult(
        moodIndex: ((output['moodIndex'] as num?)?.toInt() ?? 1).clamp(0, 3),
        moodIntensity: ((output['moodIntensity'] as num?)?.toDouble() ?? 0.5)
            .clamp(0, 1)
            .toDouble(),
        criteria:
            (output['criteria'] as String?) ??
            (output['rationale'] as String?) ??
            'AI mood review completed.',
        source: (output['modelVersion'] as String?) ?? 'ai-journal-mood',
      );
    } on AiServiceException {
      rethrow;
    } catch (_) {
      throw const AiServiceException(
        'AI mood review is unreachable. Check your internet connection and retry.',
      );
    }
  }

  static Future<TaskAiReviewResult> analyzeTaskContent(String taskTitle) async {
    if (taskTitle.trim().isEmpty) {
      throw const AiServiceException('Task title is empty.');
    }
    if (!isConfigured) {
      throw const AiServiceException('AI task review is not configured.');
    }

    try {
      final response = await http
          .post(
            Uri.parse(_flowUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': 'task-content',
              'taskTitle': taskTitle,
              'instructions':
                  'Decide if a student task title is safe and appropriate. Block self-harm intent, threats, harassment, explicit content, cheating, or harmful instructions. Return allow, label, feedback.',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
          'AI task review returned ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final output = data['result'] is Map<String, dynamic>
          ? data['result'] as Map<String, dynamic>
          : data;
      final fallbackReason = output['fallbackReason'] as String?;
      if (fallbackReason != null && fallbackReason.trim().isNotEmpty) {
        throw AiServiceException(
          'AI task fallback was refused: $fallbackReason.',
        );
      }

      return TaskAiReviewResult(
        isAllowed: output['allow'] == true,
        label: (output['label'] as String?) ?? 'AI task review',
        feedback:
            (output['feedback'] as String?) ?? 'AI reviewed this task title.',
        source: (output['modelVersion'] as String?) ?? 'ai-task-content',
      );
    } on AiServiceException {
      rethrow;
    } catch (_) {
      throw const AiServiceException(
        'AI task review is unreachable. Check your internet connection and retry.',
      );
    }
  }
}

class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TaskAiReviewResult {
  const TaskAiReviewResult({
    required this.isAllowed,
    required this.label,
    required this.feedback,
    required this.source,
  });

  factory TaskAiReviewResult.local(String title) {
    final normalized = title.toLowerCase();
    final blocked = RegExp(
      r'\b(kill myself|suicide|end my life|hurt myself|harm myself|magpakamatay|cheat on exam|hurt someone)\b',
    ).hasMatch(normalized);
    return TaskAiReviewResult(
      isAllowed: !blocked,
      label: blocked ? 'unsafe or inappropriate task wording' : 'appropriate',
      feedback: blocked
          ? 'Please rewrite this as a safe, constructive support action before saving.'
          : 'Task wording appears appropriate.',
      source: 'local-task-content',
    );
  }

  final bool isAllowed;
  final String label;
  final String feedback;
  final String source;
}

class JournalMoodResult {
  const JournalMoodResult({
    required this.moodIndex,
    required this.moodIntensity,
    required this.criteria,
    required this.source,
  });

  factory JournalMoodResult.local(String text) {
    final normalized = text.toLowerCase();
    var index = 1;
    var intensity = 0.5;
    var criteria = 'Local journal mood estimate';

    if (RegExp(
      r'\b(happy|happiest|amazing|great|grateful|excited|energized|proud|relieved|joyful|masaya|sobrang saya|salamat)\b',
    ).hasMatch(normalized)) {
      index = 3;
      intensity = 0.72;
      criteria = 'Positive emotion words were found in the journal.';
    } else if (RegExp(
      r'\b(okay|fine|calm|manageable|neutral|kaya)\b',
    ).hasMatch(normalized)) {
      index = 2;
      intensity = 0.52;
      criteria = 'Journal tone looks manageable or steady.';
    } else if (RegExp(
      r'\b(sad|tired|stress|stressed|anxious|pagod|kapoy|hirap)\b',
    ).hasMatch(normalized)) {
      index = 0;
      intensity = 0.68;
      criteria = 'Stress or low mood words were found in the journal.';
    }

    return JournalMoodResult(
      moodIndex: index,
      moodIntensity: intensity,
      criteria: criteria,
      source: 'local-journal-mood',
    );
  }

  final int moodIndex;
  final double moodIntensity;
  final String criteria;
  final String source;
}
