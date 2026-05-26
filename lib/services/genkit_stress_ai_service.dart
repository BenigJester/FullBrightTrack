import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_stress_model_service.dart';

class GenkitStressAiService {
  const GenkitStressAiService._();

  static const _flowUrl = String.fromEnvironment('GENKIT_STRESS_FLOW_URL');

  static bool get isConfigured => _flowUrl.trim().isNotEmpty;

  static Future<StressModelResult> analyze({
    required StressModelInput input,
    required List<String> warningSnippets,
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
              'avgMoodIndex': input.avgMoodIndex,
              'avgMoodIntensity': input.avgMoodIntensity,
              'avgDailySteps': input.avgDailySteps,
              'moodLogCoverage': input.moodLogCoverage,
              'journalEntryCount': input.journalEntryCount,
              'activeTaskCount': input.activeTaskCount,
              'completedTaskCount': input.completedTaskCount,
              'overdueTaskCount': input.overdueTaskCount,
              'warningSnippets': warningSnippets.take(3).toList(),
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
}
