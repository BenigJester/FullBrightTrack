import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

const _modelVersion = 'groq-llama-stress-v1';
const _fallbackVersion = 'server-local-fallback-v1';
const _groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
const _defaultGroqModel = 'llama-3.1-8b-instant';

Future<void> main() async {
  final apiKey = Platform.environment['GROQ_API_KEY']?.trim();

  final router = Router()
    ..get('/health', _health)
    ..post('/stress', (request) => _stress(request, apiKey));

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_jsonHeaders())
      .addHandler(router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('FullBrightTrack Groq backend listening on ${server.port}');
  stdout.writeln(
    'Groq API key: ${apiKey == null || apiKey.isEmpty ? 'missing' : 'configured'}',
  );
  stdout.writeln('Groq model: ${_groqModel()}');
}

Response _health(Request request) {
  return Response.ok(
    jsonEncode({
      'ok': true,
      'service': 'fullbright-stress-ai',
      'provider': 'groq',
      'model': _groqModel(),
      'modelVersion': _modelVersion,
    }),
  );
}

Future<Response> _stress(Request request, String? apiKey) async {
  Map<String, dynamic>? input;

  try {
    final body = await request.readAsString();
    final decoded = _decodeBody(body);
    final payload =
        decoded is Map<String, dynamic> &&
            decoded['data'] is Map<String, dynamic>
        ? decoded['data'] as Map<String, dynamic>
        : decoded;

    if (payload is Map<String, dynamic> &&
        payload['mode'] == 'journal-warning') {
      final result = await _journalWarningWithGroq(payload, apiKey);
      return Response.ok(jsonEncode(result));
    }

    if (payload is Map<String, dynamic> && payload['mode'] == 'journal-mood') {
      final result = await _journalMoodWithGroq(payload, apiKey);
      return Response.ok(jsonEncode(result));
    }

    if (payload is Map<String, dynamic> && payload['mode'] == 'task-content') {
      final result = await _taskContentWithGroq(payload, apiKey);
      return Response.ok(jsonEncode(result));
    }

    input = _readInputFromDecoded(decoded);
    final result = await _scoreWithGroq(input, apiKey);

    return Response.ok(jsonEncode(result));
  } catch (error) {
    if (error is _BadRequest) {
      return Response(400, body: jsonEncode({'error': error.message}));
    }

    stderr.writeln('Unexpected /stress error: $error');
    final fallback = _localScore(input ?? await _tryReadInput(request));
    fallback['fallbackReason'] = 'request_error';
    return Response.ok(jsonEncode(fallback));
  }
}

Future<Map<String, dynamic>> _taskContentWithGroq(
  Map<String, dynamic> payload,
  String? apiKey,
) async {
  final title = (payload['taskTitle'] as String?)?.trim() ?? '';
  final localBlocked = RegExp(
    r'\b(kill myself|suicide|end my life|hurt myself|harm myself|magpakamatay|cheat on exam|hurt someone)\b',
    caseSensitive: false,
  ).hasMatch(title);

  if (title.isEmpty || apiKey == null || apiKey.isEmpty) {
    return {
      'allow': title.isNotEmpty && !localBlocked,
      'label': localBlocked
          ? 'unsafe or inappropriate task wording'
          : 'appropriate',
      'feedback': localBlocked
          ? 'Please rewrite this as a safe, constructive support action before saving.'
          : 'Task wording appears appropriate.',
      'modelVersion': _fallbackVersion,
    };
  }

  try {
    final response = await http
        .post(
          Uri.parse(_groqEndpoint),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $apiKey',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': _groqModel(),
            'messages': [
              {
                'role': 'system',
                'content':
                    'Review a student task title for safety and appropriateness. Return only compact JSON.',
              },
              {
                'role': 'user',
                'content':
                    'Return exactly {"allow":true,"label":"","feedback":""}. Block self-harm intent, threats, harassment, explicit content, cheating, or harmful instructions. Title: ${jsonEncode(title)}',
              },
            ],
            'temperature': 0,
            'max_tokens': 140,
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return {
        'allow': !localBlocked,
        'label': localBlocked ? 'unsafe task wording' : 'appropriate',
        'feedback': localBlocked
            ? 'Please rewrite this as a safe support action before saving.'
            : 'Task wording appears appropriate.',
        'modelVersion': _fallbackVersion,
      };
    }

    final parsed = _extractJson(_groqMessageContent(jsonDecode(response.body)));
    if (parsed == null) {
      return {
        'allow': !localBlocked,
        'label': localBlocked ? 'unsafe task wording' : 'appropriate',
        'feedback': localBlocked
            ? 'Please rewrite this as a safe support action before saving.'
            : 'Task wording appears appropriate.',
        'modelVersion': _fallbackVersion,
      };
    }

    return {
      'allow': parsed['allow'] == true,
      'label': ((parsed['label'] as String?) ?? '').trim(),
      'feedback': ((parsed['feedback'] as String?) ?? '').trim(),
      'modelVersion': '$_modelVersion+task-content',
    };
  } catch (error) {
    return {
      'allow': !localBlocked,
      'label': localBlocked ? 'unsafe task wording' : 'appropriate',
      'feedback': localBlocked
          ? 'Please rewrite this as a safe support action before saving.'
          : 'Task wording appears appropriate.',
      'modelVersion': _fallbackVersion,
      'fallbackReason': 'task_content_failed',
      'providerError': _shortError(error.toString()),
    };
  }
}

Future<Map<String, dynamic>> _journalMoodWithGroq(
  Map<String, dynamic> payload,
  String? apiKey,
) async {
  final text = (payload['rawJournalText'] as String?)?.trim() ?? '';
  if (text.isEmpty) {
    return const {
      'moodIndex': 1,
      'moodIntensity': 0.5,
      'criteria': 'No journal text was provided.',
      'modelVersion': _fallbackVersion,
    };
  }

  if (apiKey == null || apiKey.isEmpty) {
    return {
      'moodIndex': 1,
      'moodIntensity': 0.5,
      'criteria': 'Missing Groq API key; app should use local fallback.',
      'modelVersion': _fallbackVersion,
      'fallbackReason': 'missing_groq_api_key',
    };
  }

  try {
    final response = await http
        .post(
          Uri.parse(_groqEndpoint),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $apiKey',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': _groqModel(),
            'messages': [
              {
                'role': 'system',
                'content':
                    'Estimate a student mood check-in from raw journal text. Return only compact JSON.',
              },
              {
                'role': 'user',
                'content':
                    'Understand English and Philippine languages. Return exactly {"moodIndex":1,"moodIntensity":0.5,"criteria":""}. moodIndex: 0=sad/high distress, 1=low or neutral, 2=okay/steady, 3=happy/energized. moodIntensity is 0.0 to 1.0. Journal: ${jsonEncode(text)}',
              },
            ],
            'temperature': 0,
            'max_tokens': 140,
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return {
        'moodIndex': 1,
        'moodIntensity': 0.5,
        'criteria': 'Groq mood request failed.',
        'modelVersion': _fallbackVersion,
        'fallbackReason': 'groq_http_${response.statusCode}',
      };
    }

    final parsed = _extractJson(_groqMessageContent(jsonDecode(response.body)));
    if (parsed == null) {
      return {
        'moodIndex': 1,
        'moodIntensity': 0.5,
        'criteria': 'Groq returned an invalid mood response.',
        'modelVersion': _fallbackVersion,
        'fallbackReason': 'groq_non_json_response',
      };
    }

    return {
      'moodIndex': ((_asDouble(parsed['moodIndex']) ?? 1).round()).clamp(0, 3),
      'moodIntensity': (_asDouble(parsed['moodIntensity']) ?? 0.5)
          .clamp(0, 1)
          .toDouble(),
      'criteria': ((parsed['criteria'] as String?) ?? '').trim(),
      'modelVersion': '$_modelVersion+journal-mood',
    };
  } catch (error) {
    return {
      'moodIndex': 1,
      'moodIntensity': 0.5,
      'criteria': 'Mood request failed.',
      'modelVersion': _fallbackVersion,
      'fallbackReason': 'journal_mood_failed',
      'providerError': _shortError(error.toString()),
    };
  }
}

Future<Map<String, dynamic>> _readInput(Request request) async {
  final body = await request.readAsString();
  final decoded = _decodeBody(body);
  return _readInputFromDecoded(decoded);
}

Map<String, dynamic> _readInputFromDecoded(Object? decoded) {
  if (decoded is! Map<String, dynamic>) {
    throw const _BadRequest('Expected a JSON object.');
  }

  final payload = decoded['data'] is Map<String, dynamic>
      ? decoded['data'] as Map<String, dynamic>
      : decoded;
  final baseline = payload['localBaseline'] is Map<String, dynamic>
      ? payload['localBaseline'] as Map<String, dynamic>
      : payload;
  final rawData = payload['rawData'] is Map<String, dynamic>
      ? payload['rawData'] as Map<String, dynamic>
      : <String, dynamic>{};

  return {
    'avgMoodIndex': _number(baseline, 'avgMoodIndex'),
    'avgMoodIntensity': _number(baseline, 'avgMoodIntensity'),
    'avgDailySteps': _number(baseline, 'avgDailySteps'),
    'moodLogCoverage': _number(baseline, 'moodLogCoverage'),
    'journalEntryCount': _integer(baseline, 'journalEntryCount'),
    'activeTaskCount': _integer(baseline, 'activeTaskCount'),
    'completedTaskCount': _integer(baseline, 'completedTaskCount'),
    'overdueTaskCount': _integer(baseline, 'overdueTaskCount'),
    'rawData': rawData,
    'warningSnippets': _warningSnippets(payload),
    'journalWarningWeight': _optionalNumber(payload, 'journalWarningWeight'),
    'journalWarningSeverity':
        (payload['journalWarningSeverity'] as String?) ?? 'none',
  };
}

Future<Map<String, dynamic>> _journalWarningWithGroq(
  Map<String, dynamic> payload,
  String? apiKey,
) async {
  final text = (payload['rawJournalText'] as String?)?.trim() ?? '';
  if (text.isEmpty) {
    return const {
      'severity': 'none',
      'weight': 0,
      'warningSignalTerm': '',
      'confidence': 0,
      'modelVersion': _fallbackVersion,
    };
  }

  if (apiKey == null || apiKey.isEmpty) {
    return {
      'severity': 'none',
      'weight': 0,
      'warningSignalTerm': '',
      'confidence': 0,
      'modelVersion': _fallbackVersion,
      'fallbackReason': 'missing_groq_api_key',
    };
  }

  try {
    final response = await http
        .post(
          Uri.parse(_groqEndpoint),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $apiKey',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': _groqModel(),
            'messages': [
              {
                'role': 'system',
                'content':
                    'Classify student journal safety warning severity. Return only compact JSON.',
              },
              {
                'role': 'user',
                'content':
                    'Understand English, Tagalog, Cebuano, Ilocano, Hiligaynon, and mixed Philippine languages. Return exactly {"severity":"none|stress|elevated|critical","weight":0,"warningSignalTerm":"","confidence":0}. Use a short non-graphic warningSignalTerm. Journal: ${jsonEncode(text)}',
              },
            ],
            'temperature': 0,
            'max_tokens': 140,
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return {
        'severity': 'none',
        'weight': 0,
        'warningSignalTerm': '',
        'confidence': 0,
        'modelVersion': _fallbackVersion,
        'fallbackReason': 'groq_http_${response.statusCode}',
      };
    }

    final parsed = _extractJson(_groqMessageContent(jsonDecode(response.body)));
    if (parsed == null) {
      return {
        'severity': 'none',
        'weight': 0,
        'warningSignalTerm': '',
        'confidence': 0,
        'modelVersion': _fallbackVersion,
        'fallbackReason': 'groq_non_json_response',
      };
    }

    final severity = (parsed['severity'] as String?)?.toLowerCase() ?? 'none';
    return {
      'severity': ['stress', 'elevated', 'critical'].contains(severity)
          ? severity
          : 'none',
      'weight': (_asDouble(parsed['weight']) ?? 0).clamp(0, 1).toDouble(),
      'warningSignalTerm': ((parsed['warningSignalTerm'] as String?) ?? '')
          .trim(),
      'confidence': (_asDouble(parsed['confidence']) ?? 0)
          .clamp(0, 1)
          .toDouble(),
      'modelVersion': '$_modelVersion+journal-warning',
    };
  } catch (error) {
    return {
      'severity': 'none',
      'weight': 0,
      'warningSignalTerm': '',
      'confidence': 0,
      'modelVersion': _fallbackVersion,
      'fallbackReason': 'journal_warning_failed',
      'providerError': _shortError(error.toString()),
    };
  }
}

Future<Map<String, dynamic>> _tryReadInput(Request request) async {
  try {
    return await _readInput(request);
  } catch (_) {
    return const {
      'avgMoodIndex': 0.0,
      'avgMoodIntensity': 0.0,
      'avgDailySteps': 0.0,
      'moodLogCoverage': 0.0,
      'journalEntryCount': 0,
      'activeTaskCount': 0,
      'completedTaskCount': 0,
      'overdueTaskCount': 0,
      'rawData': <String, dynamic>{},
      'warningSnippets': <String>[],
      'journalWarningWeight': 0.0,
      'journalWarningSeverity': 'none',
    };
  }
}

Future<Map<String, dynamic>> _scoreWithGroq(
  Map<String, dynamic> input,
  String? apiKey,
) async {
  if (apiKey == null || apiKey.isEmpty) {
    return _localScore(input)..['fallbackReason'] = 'missing_groq_api_key';
  }

  final local = _localScore(input);

  try {
    final response = await http
        .post(
          Uri.parse(_groqEndpoint),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $apiKey',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': _groqModel(),
            'messages': [
              {
                'role': 'system',
                'content':
                    'You score student wellness stress risk. Return only valid compact JSON.',
              },
              {'role': 'user', 'content': _prompt(input, local)},
            ],
            'temperature': 0.1,
            'max_tokens': 220,
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      stderr.writeln(
        'Groq request failed ${response.statusCode}: ${response.body}',
      );
      return local
        ..['fallbackReason'] = 'groq_http_${response.statusCode}'
        ..['providerError'] = _shortError(response.body);
    }

    final decoded = jsonDecode(response.body);
    final content = _groqMessageContent(decoded);
    final parsed = _extractJson(content);
    if (parsed == null) {
      stderr.writeln('Groq returned non-JSON content: $content');
      return local..['fallbackReason'] = 'groq_non_json_response';
    }

    final rawScore = (_asDouble(parsed['score']) ?? local['score'] as double)
        .clamp(0, 100)
        .toDouble();
    final score = _calibratedScore(input, local, rawScore);
    final confidence =
        (_asDouble(parsed['confidence']) ?? local['confidence'] as double)
            .clamp(0, 1)
            .toDouble();
    final rationale = parsed['rationale'] is List
        ? (parsed['rationale'] as List)
              .whereType<String>()
              .where((item) => item.trim().isNotEmpty)
              .take(3)
              .toList()
        : local['rationale'] as List<String>;

    return {
      'score': score,
      'rank': _rankForScore(score),
      'confidence': confidence,
      'modelVersion': _modelVersion,
      'model': _groqModel(),
      'rationale': rationale.isEmpty ? local['rationale'] : rationale,
    };
  } catch (error, stackTrace) {
    stderr.writeln('Groq request failed: $error');
    stderr.writeln(stackTrace);
    return local
      ..['fallbackReason'] = 'groq_request_failed'
      ..['providerError'] = _shortError(error.toString());
  }
}

String _prompt(Map<String, dynamic> input, Map<String, dynamic> local) {
  final sanitized = jsonEncode(input);
  return '''
Return only valid compact JSON. Do not use markdown. Do not include prose before or after the JSON.
The JSON object must use exactly these keys:
{"score": 0, "confidence": 0, "rationale": ["short signal label"]}

Use the raw recent wellness data below as the primary evidence.
Use the local numeric baseline only for calibration and safety floors.
Do not diagnose. Do not mention medical certainty.
Mood scale is important: avgMoodIndex 0 = sad/high stress risk, 1 = low mood, 2 = okay, 3 = happy/low stress risk.
avgMoodIntensity is 0 to 1. High intensity amplifies the current mood. High intensity with sad/low mood increases stress risk.
Step activity is protective. More avgDailySteps must never increase stress risk by itself.
avgDailySteps is the average across recorded positive step days, not a 30-day total.
4000 avgDailySteps or higher meets the activity goal and is highly positive/protective.
Low avgDailySteps may increase risk, but high avgDailySteps should reduce or balance activity-related risk.
Treat journalWarningWeight as numeric severity: 0 normal, about 0.3 normal stress day, about 0.65 elevated concern, 1.0 critical danger/self-harm concern.
Never return Low if avgMoodIndex is 0 and avgMoodIntensity is 0.8 or higher. That should be at least Elevated.
Never return below High if journalWarningWeight is 1.0.
score must be a number from 0 to 100.
confidence must be a number from 0 to 1.
rationale must be an array of 1 to 3 short signal labels.

Rank thresholds used by the app:
70+ High
45-69 Elevated
25-44 Moderate
<25 Low

Local baseline result for calibration:
${jsonEncode(local)}

Raw input and local baseline:
$sanitized
''';
}

Map<String, dynamic> _localScore(Map<String, dynamic> input) {
  final avgMoodIndex = input['avgMoodIndex'] as double;
  final avgMoodIntensity = input['avgMoodIntensity'] as double;
  final avgDailySteps = input['avgDailySteps'] as double;
  final moodLogCoverage = input['moodLogCoverage'] as double;
  final journalEntryCount = input['journalEntryCount'] as int;
  final activeTaskCount = input['activeTaskCount'] as int;
  final completedTaskCount = input['completedTaskCount'] as int;
  final overdueTaskCount = input['overdueTaskCount'] as int;
  final warningSnippets = input['warningSnippets'] as List<String>;
  final journalWarningWeight = (input['journalWarningWeight'] as double).clamp(
    0,
    1,
  );

  final lowMoodSignal = ((3 - avgMoodIndex).clamp(0, 3) / 3);
  final moodIntensitySignal = avgMoodIntensity.clamp(0, 1);
  final lowActivitySignal = ((4000 - avgDailySteps).clamp(0, 4000) / 4000);
  final journalSignal = min(journalEntryCount, 12) / 12;
  final overdueTaskSignal = min(overdueTaskCount, 8) / 8;
  final activeTaskSignal = min(activeTaskCount, 12) / 12;
  final completionRelief = min(completedTaskCount, 12) / 12;
  final warningSignal = max(
    journalWarningWeight,
    warningSnippets.isEmpty ? 0.0 : 0.3,
  );

  final weighted =
      lowMoodSignal * 32 +
      moodIntensitySignal * (avgMoodIndex <= 1.5 ? 16 : 7) +
      lowActivitySignal * 14 +
      journalSignal * 7 +
      overdueTaskSignal * 14 +
      activeTaskSignal * 5 +
      warningSignal * 20 -
      completionRelief * 6;
  final score = weighted.clamp(0, 100).toDouble();

  final signals = [
    moodLogCoverage > 0,
    avgDailySteps > 0,
    journalEntryCount > 0,
    activeTaskCount + completedTaskCount + overdueTaskCount > 0,
    warningSnippets.isNotEmpty,
  ].where((ready) => ready).length;
  final confidence =
      (0.1 + moodLogCoverage.clamp(0, 1) * 0.25 + signals / 5 * 0.65)
          .clamp(0, 1)
          .toDouble();

  final rationale = <String>[];
  if (journalWarningWeight >= 0.8) {
    rationale.add('critical journal warning');
  } else if (journalWarningWeight >= 0.5) {
    rationale.add('elevated journal warning');
  } else if (warningSignal > 0) {
    rationale.add('normal stress journal signal');
  }
  if (lowMoodSignal >= 0.5) rationale.add('lower recent mood');
  if (avgMoodIntensity >= 0.7 && avgMoodIndex <= 1.5) {
    rationale.add('high intensity on low mood');
  }
  if (lowActivitySignal >= 0.5) rationale.add('low step activity');
  if (overdueTaskSignal > 0) rationale.add('overdue tasks');
  if (rationale.isEmpty) rationale.add('balanced recent signals');

  return {
    'score': score,
    'rank': _rankForScore(score),
    'confidence': confidence,
    'modelVersion': _fallbackVersion,
    'rationale': rationale.take(3).toList(),
  };
}

double _calibratedScore(
  Map<String, dynamic> input,
  Map<String, dynamic> local,
  double rawScore,
) {
  final avgDailySteps = input['avgDailySteps'] as double;
  final localScore = local['score'] as double;
  final safetyFloor = _safetyFloor(input);
  var calibrated = rawScore;

  if (avgDailySteps >= 10000) {
    calibrated = min(calibrated, localScore + 4);
  } else if (avgDailySteps >= 7000) {
    calibrated = min(calibrated, localScore + 6);
  } else if (avgDailySteps >= 4000) {
    calibrated = min(calibrated, localScore + 8);
  }

  return max(calibrated, safetyFloor).clamp(0, 100).toDouble();
}

double _safetyFloor(Map<String, dynamic> input) {
  final avgMoodIndex = input['avgMoodIndex'] as double;
  final avgMoodIntensity = input['avgMoodIntensity'] as double;
  final journalWarningWeight = (input['journalWarningWeight'] as double).clamp(
    0,
    1,
  );

  if (journalWarningWeight >= 1.0) return 70;
  if (journalWarningWeight >= 0.65) return 45;
  if (avgMoodIndex <= 0.5 && avgMoodIntensity >= 0.8) return 45;
  if (journalWarningWeight >= 0.3) return 25;

  return 0;
}

String _groqModel() {
  final value = Platform.environment['GROQ_MODEL']?.trim();
  return value == null || value.isEmpty ? _defaultGroqModel : value;
}

String _groqMessageContent(Object? decoded) {
  if (decoded is! Map<String, dynamic>) return '';
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) return '';
  final first = choices.first;
  if (first is! Map<String, dynamic>) return '';
  final message = first['message'];
  if (message is! Map<String, dynamic>) return '';
  return (message['content'] as String?) ?? '';
}

Map<String, dynamic>? _extractJson(String text) {
  final trimmed = text.trim();
  final direct = _decodeMap(trimmed);
  if (direct != null) return direct;

  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) return null;

  return _decodeMap(trimmed.substring(start, end + 1));
}

Map<String, dynamic>? _decodeMap(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

Object? _decodeBody(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    final repaired = _repairPowerShellCurlJson(body);
    if (repaired == body) rethrow;
    return jsonDecode(repaired);
  }
}

String _repairPowerShellCurlJson(String body) {
  var repaired = body.trim();

  repaired = repaired.replaceAllMapped(
    RegExp(r'([,{]\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*:)'),
    (match) => '${match[1]}"${match[2]}"${match[3]}',
  );
  repaired = repaired.replaceAllMapped(
    RegExp(r':\s*\[([A-Za-z][A-Za-z0-9 _-]*)\]'),
    (match) => ':["${match[1]}"]',
  );

  return repaired;
}

double _number(Map<String, dynamic> payload, String key) {
  final value = _asDouble(payload[key]);
  if (value == null || value.isNaN || value.isInfinite) {
    throw _BadRequest('Missing numeric field: $key');
  }

  return value;
}

double _optionalNumber(Map<String, dynamic> payload, String key) {
  final value = _asDouble(payload[key]);
  if (value == null || value.isNaN || value.isInfinite) return 0;

  return value.clamp(0, 1).toDouble();
}

int _integer(Map<String, dynamic> payload, String key) {
  final value = _asDouble(payload[key]);
  if (value == null || value.isNaN || value.isInfinite) {
    throw _BadRequest('Missing integer field: $key');
  }

  return value.round().clamp(0, 1000000);
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

List<String> _warningSnippets(Map<String, dynamic> payload) {
  final raw = payload['warningSnippets'];
  if (raw is! List) return const [];

  return raw
      .whereType<String>()
      .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((value) => value.isNotEmpty)
      .map(
        (value) =>
            value.length <= 120 ? value : '${value.substring(0, 120)}...',
      )
      .take(3)
      .toList();
}

String _rankForScore(double score) {
  if (score >= 70) return 'High';
  if (score >= 45) return 'Elevated';
  if (score >= 25) return 'Moderate';
  return 'Low';
}

String _shortError(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.length <= 220
      ? normalized
      : '${normalized.substring(0, 220)}...';
}

Middleware _jsonHeaders() {
  return (handler) {
    return (request) async {
      final response = await handler(request);
      return response.change(
        headers: {
          ...response.headers,
          HttpHeaders.contentTypeHeader: 'application/json',
        },
      );
    };
  };
}

class _BadRequest implements Exception {
  const _BadRequest(this.message);

  final String message;
}
