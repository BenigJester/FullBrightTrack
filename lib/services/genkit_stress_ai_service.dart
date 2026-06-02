import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_stress_model_service.dart';
import 'journal_warning_service.dart';

class GenkitStressAiService {
  const GenkitStressAiService._();

  static const _flowUrl = String.fromEnvironment('GENKIT_STRESS_FLOW_URL');

  static bool get isConfigured => _flowUrl.trim().isNotEmpty;

  static Future<StressModelResult> analyze({
    required StressModelInput input,
    required Map<String, dynamic> rawData,
    required List<String> warningSnippets,
    required double journalWarningWeight,
    required String journalWarningSeverity,
  }) async {
    if (!isConfigured) {
      return LocalStressModelService.analyze(input);
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
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LocalStressModelService.analyze(input);
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final output = data['result'] is Map<String, dynamic>
          ? data['result'] as Map<String, dynamic>
          : data;

      return StressModelResult(
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
    } catch (_) {
      return LocalStressModelService.analyze(input);
    }
  }

  static Future<JournalWarningSummary> analyzeJournalWarning(
    String journalText,
  ) async {
    final fallback = JournalWarningService.analyze(journalText);
    if (!isConfigured || journalText.trim().isEmpty) return fallback;

    try {
      final response = await http
          .post(
            Uri.parse(_flowUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': 'journal-warning',
              'rawJournalText': journalText,
              'instructions':
                  'Classify safety severity from raw student journal text. Understand English, Tagalog, Cebuano, Ilocano, Hiligaynon, and mixed Philippine languages. Return severity, weight, and warningSignalTerm.',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallback;
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final output = data['result'] is Map<String, dynamic>
          ? data['result'] as Map<String, dynamic>
          : data;

      return JournalWarningService.fromAi(
        severity: (output['severity'] as String?) ?? 'none',
        weight: ((output['weight'] as num?)?.toDouble() ?? fallback.weight)
            .clamp(0, 1)
            .toDouble(),
        warningSignalTerm:
            (output['warningSignalTerm'] as String?) ??
            fallback.snippets.firstOrNull ??
            '',
      );
    } catch (_) {
      return fallback;
    }
  }

  static Future<JournalMoodResult> analyzeJournalMood(
    String journalText,
  ) async {
    final fallback = JournalMoodResult.local(journalText);
    if (!isConfigured || journalText.trim().isEmpty) return fallback;

    try {
      final response = await http
          .post(
            Uri.parse(_flowUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': 'journal-mood',
              'rawJournalText': journalText,
              'instructions':
                  'Read the raw journal and estimate moodIndex 0 sad, 1 low/neutral, 2 okay, 3 happy, plus moodIntensity 0.0 to 1.0. Return criteria.',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallback;
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final output = data['result'] is Map<String, dynamic>
          ? data['result'] as Map<String, dynamic>
          : data;

      return JournalMoodResult(
        moodIndex:
            ((output['moodIndex'] as num?)?.toInt() ?? fallback.moodIndex)
                .clamp(0, 3),
        moodIntensity:
            ((output['moodIntensity'] as num?)?.toDouble() ??
                    fallback.moodIntensity)
                .clamp(0, 1)
                .toDouble(),
        criteria:
            (output['criteria'] as String?) ??
            (output['rationale'] as String?) ??
            fallback.criteria,
        source: (output['modelVersion'] as String?) ?? 'ai-journal-mood',
      );
    } catch (_) {
      return fallback;
    }
  }

  static Future<TaskAiReviewResult> analyzeTaskContent(String taskTitle) async {
    final fallback = TaskAiReviewResult.local(taskTitle);
    if (!isConfigured || taskTitle.trim().isEmpty) return fallback;

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
        return fallback;
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final output = data['result'] is Map<String, dynamic>
          ? data['result'] as Map<String, dynamic>
          : data;

      return TaskAiReviewResult(
        isAllowed: output['allow'] == true,
        label: (output['label'] as String?) ?? fallback.label,
        feedback: (output['feedback'] as String?) ?? fallback.feedback,
        source: (output['modelVersion'] as String?) ?? 'ai-task-content',
      );
    } catch (_) {
      return fallback;
    }
  }
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
      r'\b(happy|great|grateful|excited|proud|relieved|masaya|salamat)\b',
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
