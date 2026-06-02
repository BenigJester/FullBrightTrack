import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

const _modelVersion = 'groq-llama-stress-v1';
const _fallbackVersion = 'server-local-fallback-v1';
const _groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
const _defaultGroqModel = 'llama-3.1-8b-instant';
const _stressGroqCooldown = Duration(seconds: 70);
const _pendingRegistrationTtl = Duration(minutes: 30);
const _passwordResetTtl = Duration(minutes: 20);

DateTime? _lastGroqStressStartedAt;
String? _lastGroqStressInputKey;
Map<String, dynamic>? _lastGroqStressResult;
_FirebaseBackend? _firebaseBackend;

Future<void> main() async {
  final apiKey = Platform.environment['GROQ_API_KEY']?.trim();
  final googleApiKey = Platform.environment['GOOGLE_API_KEY']?.trim();
  _firebaseBackend = _FirebaseBackend.fromEnvironment();

  final router = Router()
    ..get('/health', _health)
    ..post('/stress', (request) => _stress(request, apiKey))
    ..post('/start-registration', _startRegistration)
    ..get('/confirm-registration', _confirmRegistration)
    ..post('/complete-registration', _completeRegistration)
    ..post('/request-password-reset', _requestPasswordReset)
    ..get('/confirm-password-reset', _confirmPasswordReset)
    ..post('/complete-password-reset', _completePasswordReset)
    ..post('/admin-alert-worker', _adminAlertWorker)
    ..post('/developer-delete-user', _developerDeleteUser);

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
  if ((apiKey == null || apiKey.isEmpty) &&
      googleApiKey != null &&
      googleApiKey.isNotEmpty) {
    stdout.writeln(
      'Note: GOOGLE_API_KEY is ignored by this backend. Set GROQ_API_KEY for AI calls, or leave it empty to use local fallback scoring.',
    );
  }
  stdout.writeln('Groq model: ${_groqModel()}');
  stdout.writeln(
    'Firebase backend: ${_firebaseBackend == null ? 'not configured' : 'configured'}',
  );

  final workerIntervalSeconds = int.tryParse(
    Platform.environment['ADMIN_ALERT_WORKER_INTERVAL_SECONDS'] ?? '',
  );
  if (workerIntervalSeconds != null && workerIntervalSeconds > 0) {
    Timer.periodic(Duration(seconds: workerIntervalSeconds), (_) {
      unawaited(_sendPendingAdminAlerts());
    });
    stdout.writeln(
      'Admin alert worker polling every $workerIntervalSeconds seconds',
    );
  }
}

Response _health(Request request) {
  return Response.ok(
    jsonEncode({
      'ok': true,
      'service': 'fullbright-stress-ai',
      'provider': 'groq',
      'model': _groqModel(),
      'modelVersion': _modelVersion,
      'firebaseBackendConfigured': _firebaseBackend != null,
    }),
  );
}

Future<Response> _startRegistration(Request request) async {
  try {
    final backend = _requireFirebaseBackend();
    final payload = await _readJsonObject(request);
    final email = _emailFromPayload(payload);
    final mailer = _SmtpEmailSender.fromEnvironment();
    if (mailer == null) {
      throw const _BadRequest(
        'Email delivery is not configured. Set SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, and SMTP_FROM_EMAIL.',
      );
    }
    final id = _randomToken(12);
    final token = _randomToken(32);
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(_pendingRegistrationTtl);
    final confirmationUrl =
        '${_publicBaseUrl(request)}/confirm-registration?id=${Uri.encodeComponent(id)}&token=${Uri.encodeComponent(token)}';

    await backend.setDocument('pending_registrations/$id', {
      'email': email,
      'tokenHash': _hashToken(token),
      'status': 'pending',
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    await mailer.sendRegistrationConfirmation(
      toEmail: email,
      confirmationUrl: confirmationUrl,
      expiresAt: expiresAt,
    );

    await backend.updateDocument('pending_registrations/$id', {
      'emailSentAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    stdout.writeln(
      'Registration confirmation email sent to $email',
    );
    return _jsonResponse({
      'ok': true,
      'email': email,
      'requestId': id,
      'confirmationUrl':
          Platform.environment['EMAIL_DEBUG_RETURN_LINK'] == 'true'
          ? confirmationUrl
          : '',
      'expiresAt': expiresAt.toIso8601String(),
      'note':
          'Confirmation email sent. The app creates the Firebase Auth account only after confirmation.',
    });
  } catch (error) {
    return _errorResponse(error);
  }
}

Future<Response> _confirmRegistration(Request request) async {
  try {
    final backend = _requireFirebaseBackend();
    final id = request.url.queryParameters['id']?.trim() ?? '';
    final token = request.url.queryParameters['token']?.trim() ?? '';
    if (id.isEmpty || token.isEmpty) {
      return Response(400, body: 'Missing confirmation id or token.');
    }

    final doc = await backend.getDocument('pending_registrations/$id');
    if (doc == null) {
      return Response(404, body: 'Confirmation request not found.');
    }
    final status = doc['status'] as String? ?? 'pending';
    if (status == 'confirmed') {
      return Response(409, body: 'This confirmation link was already used.');
    }
    if (_isExpired(doc['expiresAt'])) {
      await backend.updateDocument('pending_registrations/$id', {
        'status': 'expired',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      return Response(410, body: 'This confirmation link has expired.');
    }
    if (doc['tokenHash'] != _hashToken(token)) {
      return Response(403, body: 'Invalid confirmation token.');
    }

    await backend.updateDocument('pending_registrations/$id', {
      'status': 'confirmed',
      'confirmedAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return Response.ok(
      'Email confirmed. You can now create the Firebase Auth account in the app.',
    );
  } catch (error) {
    return _errorResponse(error);
  }
}

Future<Response> _completeRegistration(Request request) async {
  try {
    final backend = _requireFirebaseBackend();
    final payload = await _readJsonObject(request);
    final id = ((payload['requestId'] as String?) ?? '').trim();
    final email = _emailFromPayload(payload);
    if (id.isEmpty) {
      throw const _BadRequest('Registration request id is required.');
    }

    final doc = await backend.getDocument('pending_registrations/$id');
    if (doc == null) {
      throw const _BadRequest('Confirmation request was not found.');
    }
    if ((doc['email'] as String?)?.toLowerCase() != email.toLowerCase()) {
      throw const _BadRequest('This confirmation belongs to another email.');
    }

    final status = doc['status'] as String? ?? 'pending';
    if (status != 'confirmed') {
      throw const _BadRequest(
        'Email is not confirmed yet. Open the confirmation link first.',
      );
    }

    await backend.updateDocument('pending_registrations/$id', {
      'lastVerifiedAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    return _jsonResponse({
      'ok': true,
      'email': email,
      'requestId': id,
      'message': 'Email is confirmed and ready for Firebase Auth creation.',
    });
  } catch (error) {
    return _errorResponse(error);
  }
}

Future<Response> _requestPasswordReset(Request request) async {
  try {
    final backend = _requireFirebaseBackend();
    final payload = await _readJsonObject(request);
    final email = _emailFromPayload(payload);
    final user = await backend.lookupUserByEmail(email);
    if (user == null) {
      return _jsonResponse({
        'ok': true,
        'email': email,
        'note':
            'If this email exists, a reset link can be generated. No account was found in this demo backend.',
      });
    }

    final id = _randomToken(12);
    final token = _randomToken(32);
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(_passwordResetTtl);
    final resetUrl =
        '${_publicBaseUrl(request)}/confirm-password-reset?id=${Uri.encodeComponent(id)}&token=${Uri.encodeComponent(token)}';

    await backend.setDocument('password_reset_requests/$id', {
      'email': email,
      'uid': user['localId'],
      'tokenHash': _hashToken(token),
      'status': 'pending',
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    stdout.writeln('Password reset link for $email: $resetUrl');
    return _jsonResponse({
      'ok': true,
      'email': email,
      'requestId': id,
      'resetUrl': resetUrl,
      'expiresAt': expiresAt.toIso8601String(),
    });
  } catch (error) {
    return _errorResponse(error);
  }
}

Future<Response> _confirmPasswordReset(Request request) async {
  try {
    final backend = _requireFirebaseBackend();
    final reset = await _validPasswordResetRequest(backend, request);
    return _jsonResponse({
      'ok': true,
      'email': reset['email'],
      'requestId': request.url.queryParameters['id'],
      'message':
          'Token is valid. Submit id, token, and newPassword to /complete-password-reset.',
    });
  } catch (error) {
    return _errorResponse(error);
  }
}

Future<Response> _completePasswordReset(Request request) async {
  try {
    final backend = _requireFirebaseBackend();
    final payload = await _readJsonObject(request);
    final reset = await _validPasswordResetRequest(
      backend,
      request,
      queryOverride: {
        'id': payload['id'] as String? ?? '',
        'token': payload['token'] as String? ?? '',
      },
    );
    final newPassword = (payload['newPassword'] as String?)?.trim() ?? '';
    if (newPassword.length < 6) {
      throw const _BadRequest('Password must be at least 6 characters.');
    }

    await backend.updateUserPassword(reset['uid'] as String, newPassword);
    await backend.updateDocument('password_reset_requests/${payload['id']}', {
      'status': 'used',
      'usedAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return _jsonResponse({'ok': true, 'message': 'Password was updated.'});
  } catch (error) {
    return _errorResponse(error);
  }
}

Future<Response> _adminAlertWorker(Request request) async {
  try {
    final result = await _sendPendingAdminAlerts();
    return _jsonResponse(result);
  } catch (error) {
    return _errorResponse(error);
  }
}

Future<Response> _developerDeleteUser(Request request) async {
  try {
    final backend = _requireFirebaseBackend();
    final adminUid = await _requireAdminToken(backend, request);
    final payload = await _readJsonObject(request);
    final rawUid = ((payload['uid'] as String?) ?? '').trim();
    final rawEmail = ((payload['email'] as String?) ?? '').trim().toLowerCase();

    if (rawUid.isEmpty && rawEmail.isEmpty) {
      throw const _BadRequest('Enter a target user UID or email.');
    }

    final targetUser = rawUid.isNotEmpty
        ? await backend.lookupUserByUid(rawUid)
        : await backend.lookupUserByEmail(rawEmail);
    if (targetUser == null) {
      throw const _BadRequest('Target Firebase Auth user was not found.');
    }

    final targetUid = (targetUser['localId'] as String?) ?? '';
    final targetEmail = (targetUser['email'] as String?) ?? rawEmail;
    if (targetUid.isEmpty) {
      throw const _BadRequest('Target Firebase Auth user has no UID.');
    }
    if (targetUid == adminUid) {
      throw const _BadRequest('You cannot delete your own developer login.');
    }

    await backend.deleteAuthUser(targetUid);

    return _jsonResponse({
      'ok': true,
      'deletedUid': targetUid,
      'deletedEmail': targetEmail,
      'message':
          'Firebase Auth login credentials were deleted. Firestore profile data was not deleted.',
    });
  } catch (error) {
    return _errorResponse(error);
  }
}

_FirebaseBackend _requireFirebaseBackend() {
  final backend = _firebaseBackend;
  if (backend == null) {
    throw const _BadRequest(
      'Firebase backend is not configured. Set FIREBASE_SERVICE_ACCOUNT_JSON.',
    );
  }
  return backend;
}

Future<String> _requireAdminToken(
  _FirebaseBackend backend,
  Request request,
) async {
  final header = request.headers[HttpHeaders.authorizationHeader] ?? '';
  final match = RegExp(
    r'^Bearer\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(header);
  final idToken = match?.group(1)?.trim() ?? '';
  if (idToken.isEmpty) {
    throw const _BadRequest('Admin authorization token is required.');
  }

  final adminUser = await backend.lookupUserByIdToken(idToken);
  final adminUid = (adminUser?['localId'] as String?) ?? '';
  if (adminUid.isEmpty) {
    throw const _BadRequest('Invalid admin authorization token.');
  }

  final adminProfile = await backend.getDocument('users/$adminUid');
  if (adminProfile?['isAdmin'] != true) {
    throw const _BadRequest('This account is not allowed to manage users.');
  }

  return adminUid;
}

Future<Map<String, dynamic>> _readJsonObject(Request request) async {
  final body = await request.readAsString();
  final decoded = body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const _BadRequest('JSON object body is required.');
  }
  return decoded;
}

String _emailFromPayload(Map<String, dynamic> payload) {
  final email = ((payload['email'] as String?) ?? '').trim().toLowerCase();
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    throw const _BadRequest('A valid email is required.');
  }
  return email;
}

String _publicBaseUrl(Request request) {
  final configured = Platform.environment['PUBLIC_BASE_URL']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return configured.replaceAll(RegExp(r'/+$'), '');
  }
  return '${request.requestedUri.scheme}://${request.requestedUri.authority}';
}

String _randomToken(int bytes) {
  final random = Random.secure();
  final values = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64UrlEncode(values).replaceAll('=', '');
}

String _hashToken(String token) {
  return sha256.convert(utf8.encode(token)).toString();
}

bool _isExpired(Object? value) {
  if (value is! String) return true;
  final expiresAt = DateTime.tryParse(value);
  if (expiresAt == null) return true;
  return DateTime.now().toUtc().isAfter(expiresAt.toUtc());
}

Future<Map<String, dynamic>> _validPasswordResetRequest(
  _FirebaseBackend backend,
  Request request, {
  Map<String, String>? queryOverride,
}) async {
  final query = queryOverride ?? request.url.queryParameters;
  final id = query['id']?.trim() ?? '';
  final token = query['token']?.trim() ?? '';
  if (id.isEmpty || token.isEmpty) {
    throw const _BadRequest('Missing reset id or token.');
  }

  final doc = await backend.getDocument('password_reset_requests/$id');
  if (doc == null) throw const _BadRequest('Reset request was not found.');
  final status = doc['status'] as String? ?? 'pending';
  if (status == 'used') {
    throw const _BadRequest('This reset link was already used.');
  }
  if (_isExpired(doc['expiresAt'])) {
    await backend.updateDocument('password_reset_requests/$id', {
      'status': 'expired',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    throw const _BadRequest('This reset link has expired.');
  }
  if (doc['tokenHash'] != _hashToken(token)) {
    throw const _BadRequest('Invalid reset token.');
  }
  return doc;
}

Future<Map<String, dynamic>> _sendPendingAdminAlerts() async {
  final backend = _requireFirebaseBackend();
  final alerts = await backend.pendingAdminAlerts(limit: 10);
  final tokens = await backend.adminFcmTokens();
  var sentAlerts = 0;
  var successCount = 0;
  var failureCount = 0;

  if (tokens.isEmpty) {
    for (final alert in alerts) {
      await backend.updateDocument(alert.path, {
        'pushStatus': 'no_admin_tokens',
        'pushUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
    return {
      'ok': true,
      'alertsChecked': alerts.length,
      'sentAlerts': 0,
      'successCount': 0,
      'failureCount': 0,
      'tokenCount': 0,
    };
  }

  for (final alert in alerts) {
    final data = alert.data;
    final displayName = (data['displayName'] as String?) ?? 'Student';
    final rank = (data['stressRank'] as String?) ?? 'High';
    var alertSuccess = 0;
    var alertFailure = 0;

    for (final token in tokens) {
      final sent = await backend.sendFcm(
        token: token,
        title: 'Wellness signal needs review',
        body: '$displayName has a $rank stress signal.',
        data: {
          'type': 'admin_safety_alert',
          'alertId': alert.id,
          'userId': (data['userId'] as String?) ?? '',
          'stressRank': rank,
        },
      );
      if (sent) {
        alertSuccess++;
      } else {
        alertFailure++;
      }
    }

    await backend.updateDocument(alert.path, {
      'pushStatus': alertSuccess > 0 ? 'sent' : 'failed',
      'pushSuccessCount': alertSuccess,
      'pushFailureCount': alertFailure,
      'pushUpdatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    sentAlerts++;
    successCount += alertSuccess;
    failureCount += alertFailure;
  }

  return {
    'ok': true,
    'alertsChecked': alerts.length,
    'sentAlerts': sentAlerts,
    'successCount': successCount,
    'failureCount': failureCount,
    'tokenCount': tokens.length,
  };
}

Response _jsonResponse(Map<String, dynamic> body) {
  return Response.ok(jsonEncode(body));
}

Response _errorResponse(Object error) {
  final status = error is _BadRequest ? 400 : 500;
  return Response(
    status,
    body: jsonEncode({'ok': false, 'error': error.toString()}),
    headers: {'Content-Type': 'application/json'},
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
    final inputKey = jsonEncode(input);
    if (_shouldUseStressFallbackNow()) {
      final cached = _lastGroqStressResult;
      if (cached != null && _lastGroqStressInputKey == inputKey) {
        return Response.ok(
          jsonEncode({...cached, 'cacheStatus': 'reused_recent_groq_result'}),
        );
      }
      final fallback = _localScore(input)
        ..['fallbackReason'] = 'server_stress_groq_cooldown_no_cache';
      return Response.ok(jsonEncode(fallback));
    }

    _lastGroqStressStartedAt = DateTime.now();
    final result = await _scoreWithGroq(input, apiKey);
    if ((result['modelVersion'] as String?) == _modelVersion) {
      _lastGroqStressInputKey = inputKey;
      _lastGroqStressResult = Map<String, dynamic>.from(result);
    }

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
  final adminResolutionContext =
      payload['adminResolutionContext'] is Map<String, dynamic>
      ? payload['adminResolutionContext'] as Map<String, dynamic>
      : rawData['adminResolutionContext'] is Map<String, dynamic>
      ? rawData['adminResolutionContext'] as Map<String, dynamic>
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
    'adminResolutionContext': adminResolutionContext,
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
                    'Understand English, Tagalog, Cebuano, Ilocano, Hiligaynon, Waray, Kapampangan, Pangasinan, Bicolano, and mixed Philippine languages. Detect self-harm, suicide, harm toward another person, threats, violent intent, coercion, harassment, and explicit unsafe wording. If the wording is clearly slang, a harmless joke, quoted media, academic discussion, or not an actual safety concern, return severity none with confidence. Return exactly {"severity":"none|stress|elevated|critical","weight":0,"warningSignalTerm":"","confidence":0}. Use a short non-graphic warningSignalTerm such as "harm toward others" or "explicit unsafe wording". Journal: ${jsonEncode(text)}',
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

bool _shouldUseStressFallbackNow() {
  final lastStarted = _lastGroqStressStartedAt;
  if (lastStarted == null) return false;
  return DateTime.now().difference(lastStarted) < _stressGroqCooldown;
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

Use compact raw recent wellness data as primary evidence.
Use the local numeric baseline for calibration and safety floors.
Do not diagnose. Do not mention medical certainty.
Mood scale is important: avgMoodIndex 0 = sad/high stress risk, 1 = low mood, 2 = okay, 3 = happy/low stress risk.
avgMoodIntensity is 0 to 1. High intensity amplifies the current mood. High intensity with sad/low mood increases stress risk, but high intensity with happy/energized mood should reduce stress risk.
Step activity is protective. More avgDailySteps must never increase stress risk by itself.
avgDailySteps is the average across recorded positive step days, not a 30-day total.
4000 avgDailySteps or higher meets the activity goal and is highly positive/protective.
Low avgDailySteps may increase risk, but high avgDailySteps should reduce or balance activity-related risk.
Treat journalWarningWeight as numeric severity: 0 normal, about 0.3 normal stress day, about 0.65 elevated concern, 1.0 critical danger/self-harm concern.
If adminResolutionContext.hasResolvedWarning is true and activeWarningCount is 0, matching resolved warning journals are historical resolved events after therapist/support contact. Do not treat those resolved journals as active current danger. Use fresh unresolved mood, journal, task, and activity signals for the current score.
Never return Low if avgMoodIndex is 0 and avgMoodIntensity is 0.8 or higher. That should be at least Elevated.
Never return below High if journalWarningWeight is 1.0 for an active unresolved warning.
score must be a number from 0 to 100.
confidence must be a number from 0 to 1.
rationale must be an array of 1 to 3 short signal labels.

Rank thresholds used by the app:
70+ High
45-69 Elevated
25-44 Moderate
<25 Low

Local baseline result:
${jsonEncode(local)}

Compact raw input and baseline:
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
  final moodIntensityWeight = avgMoodIndex <= 1.5 ? 16 : -9;

  final weighted =
      lowMoodSignal * 32 +
      moodIntensitySignal * moodIntensityWeight +
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
  if (_hasResolvedSupportWithoutActiveWarning(input)) {
    calibrated = min(calibrated, localScore + 12);
  }

  if (avgDailySteps >= 10000) {
    calibrated = min(calibrated, localScore + 4);
  } else if (avgDailySteps >= 7000) {
    calibrated = min(calibrated, localScore + 6);
  } else if (avgDailySteps >= 4000) {
    calibrated = min(calibrated, localScore + 8);
  }

  return max(calibrated, safetyFloor).clamp(0, 100).toDouble();
}

bool _hasResolvedSupportWithoutActiveWarning(Map<String, dynamic> input) {
  final context = input['adminResolutionContext'];
  if (context is! Map<String, dynamic>) return false;
  final hasResolved = context['hasResolvedWarning'] == true;
  final activeWarningCount = context['activeWarningCount'] is num
      ? (context['activeWarningCount'] as num).toInt()
      : 0;
  final journalWarningWeight = (input['journalWarningWeight'] as double).clamp(
    0,
    1,
  );
  return hasResolved && activeWarningCount <= 0 && journalWarningWeight <= 0;
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

class _SmtpEmailSender {
  const _SmtpEmailSender({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.fromEmail,
    required this.fromName,
    required this.useStartTls,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String fromEmail;
  final String fromName;
  final bool useStartTls;

  static _SmtpEmailSender? fromEnvironment() {
    final host = Platform.environment['SMTP_HOST']?.trim() ?? '';
    final username = Platform.environment['SMTP_USERNAME']?.trim() ?? '';
    final password = Platform.environment['SMTP_PASSWORD']?.trim() ?? '';
    final fromEmail =
        Platform.environment['SMTP_FROM_EMAIL']?.trim().isNotEmpty == true
        ? Platform.environment['SMTP_FROM_EMAIL']!.trim()
        : username;
    final fromName =
        Platform.environment['SMTP_FROM_NAME']?.trim().isNotEmpty == true
        ? Platform.environment['SMTP_FROM_NAME']!.trim()
        : 'FullBrightTrack';
    final port =
        int.tryParse(Platform.environment['SMTP_PORT'] ?? '') ?? 587;
    final useStartTls =
        (Platform.environment['SMTP_STARTTLS'] ?? 'true').toLowerCase() !=
        'false';

    if (host.isEmpty ||
        username.isEmpty ||
        password.isEmpty ||
        fromEmail.isEmpty) {
      return null;
    }

    return _SmtpEmailSender(
      host: host,
      port: port,
      username: username,
      password: password,
      fromEmail: fromEmail,
      fromName: fromName,
      useStartTls: useStartTls,
    );
  }

  Future<void> sendRegistrationConfirmation({
    required String toEmail,
    required String confirmationUrl,
    required DateTime expiresAt,
  }) async {
    final subject = 'Confirm your FullBrightTrack registration';
    final textBody =
        '''
Hello,

Please confirm your FullBrightTrack registration by opening this link:

$confirmationUrl

This link expires at ${expiresAt.toLocal()}.

If you did not request this account, you can ignore this email.
''';

    await _send(
      toEmail: toEmail,
      subject: subject,
      textBody: textBody,
    );
  }

  Future<void> _send({
    required String toEmail,
    required String subject,
    required String textBody,
  }) async {
    final client = await _SmtpClient.connect(
      host: host,
      port: port,
      useImplicitTls: port == 465,
    );

    try {
      await client.expect([220]);
      await client.command('EHLO fullbrighttrack.local', [250]);

      if (useStartTls && port != 465) {
        await client.command('STARTTLS', [220]);
        await client.upgradeToTls(host);
        await client.command('EHLO fullbrighttrack.local', [250]);
      }

      await client.command('AUTH LOGIN', [334]);
      await client.command(base64Encode(utf8.encode(username)), [334]);
      await client.command(base64Encode(utf8.encode(password)), [235]);
      await client.command('MAIL FROM:<$fromEmail>', [250]);
      await client.command('RCPT TO:<$toEmail>', [250, 251]);
      await client.command('DATA', [354]);
      await client.writeData(
        _emailMessage(
          toEmail: toEmail,
          subject: subject,
          textBody: textBody,
        ),
      );
      await client.expect([250]);
      await client.command('QUIT', [221]);
    } finally {
      await client.close();
    }
  }

  String _emailMessage({
    required String toEmail,
    required String subject,
    required String textBody,
  }) {
    final safeFromName = fromName.replaceAll('"', "'");
    final escapedBody = textBody.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    return [
      'From: "$safeFromName" <$fromEmail>',
      'To: <$toEmail>',
      'Subject: $subject',
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=utf-8',
      'Content-Transfer-Encoding: 8bit',
      '',
      escapedBody,
    ].join('\r\n');
  }
}

class _SmtpClient {
  _SmtpClient._(this._socket) {
    _lines = StreamIterator(
      utf8.decoder.bind(_socket).transform(const LineSplitter()),
    );
  }

  Socket _socket;
  late StreamIterator<String> _lines;

  static Future<_SmtpClient> connect({
    required String host,
    required int port,
    required bool useImplicitTls,
  }) async {
    final socket = useImplicitTls
        ? await SecureSocket.connect(host, port, timeout: const Duration(seconds: 12))
        : await Socket.connect(host, port, timeout: const Duration(seconds: 12));
    return _SmtpClient._(socket);
  }

  Future<void> upgradeToTls(String host) async {
    await _lines.cancel();
    _socket = await SecureSocket.secure(_socket, host: host);
    _lines = StreamIterator(
      utf8.decoder.bind(_socket).transform(const LineSplitter()),
    );
  }

  Future<void> command(String value, List<int> expectedCodes) async {
    _socket.write('$value\r\n');
    await _socket.flush();
    await expect(expectedCodes);
  }

  Future<void> writeData(String message) async {
    final escaped = message
        .split('\r\n')
        .map((line) => line.startsWith('.') ? '.$line' : line)
        .join('\r\n');
    _socket.write('$escaped\r\n.\r\n');
    await _socket.flush();
  }

  Future<void> expect(List<int> expectedCodes) async {
    final response = await _readResponse();
    if (!expectedCodes.contains(response.code)) {
      throw _BadRequest('SMTP error ${response.code}: ${response.message}');
    }
  }

  Future<_SmtpResponse> _readResponse() async {
    final lines = <String>[];
    while (await _lines.moveNext()) {
      final line = _lines.current;
      lines.add(line);
      if (line.length >= 4 && line[3] == ' ') {
        final code = int.tryParse(line.substring(0, 3)) ?? 0;
        return _SmtpResponse(code, lines.join('\n'));
      }
      if (line.length < 4) {
        return _SmtpResponse(0, lines.join('\n'));
      }
    }
    return _SmtpResponse(0, 'SMTP connection closed.');
  }

  Future<void> close() async {
    await _lines.cancel();
    await _socket.close();
  }
}

class _SmtpResponse {
  const _SmtpResponse(this.code, this.message);

  final int code;
  final String message;
}

class _FirebaseBackend {
  _FirebaseBackend._(this._credentials, this.projectId);

  final ServiceAccountCredentials _credentials;
  final String projectId;
  AuthClient? _client;

  static _FirebaseBackend? fromEnvironment() {
    final raw = Platform.environment['FIREBASE_SERVICE_ACCOUNT_JSON']?.trim();
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final credentials = ServiceAccountCredentials.fromJson(decoded);
    final projectId =
        Platform.environment['FIREBASE_PROJECT_ID']?.trim() ??
        (decoded['project_id'] as String?)?.trim() ??
        '';
    if (projectId.isEmpty) return null;

    return _FirebaseBackend._(credentials, projectId);
  }

  Future<AuthClient> _authClient() async {
    final current = _client;
    if (current != null) return current;

    final client = await clientViaServiceAccount(_credentials, const [
      'https://www.googleapis.com/auth/cloud-platform',
    ]);
    _client = client;
    return client;
  }

  String get _documentsBase =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  Future<void> setDocument(String path, Map<String, dynamic> data) async {
    final client = await _authClient();
    final response = await client.patch(
      Uri.parse('$_documentsBase/$path'),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({'fields': _encodeFields(data)}),
    );
    _throwIfBad(response, 'set Firestore document');
  }

  Future<void> updateDocument(String path, Map<String, dynamic> data) async {
    final client = await _authClient();
    final mask = data.keys
        .map((key) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(key)}')
        .join('&');
    final uri = Uri.parse('$_documentsBase/$path?$mask');
    final response = await client.patch(
      uri,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({'fields': _encodeFields(data)}),
    );
    _throwIfBad(response, 'update Firestore document');
  }

  Future<Map<String, dynamic>?> getDocument(String path) async {
    final client = await _authClient();
    final response = await client.get(Uri.parse('$_documentsBase/$path'));
    if (response.statusCode == 404) return null;
    _throwIfBad(response, 'get Firestore document');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return _decodeFields(decoded['fields'] as Map<String, dynamic>?);
  }

  Future<List<_AdminAlertRecord>> pendingAdminAlerts({int limit = 10}) async {
    final results = await _runQuery({
      'structuredQuery': {
        'from': [
          {'collectionId': 'admin_alerts'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'status'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'active'},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'pushStatus'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'pending'},
                },
              },
            ],
          },
        },
        'limit': limit,
      },
    });

    return results.map((document) {
      final name = document['name'] as String;
      final path = _relativePath(name);
      return _AdminAlertRecord(
        id: path.split('/').last,
        path: path,
        data: _decodeFields(document['fields'] as Map<String, dynamic>?),
      );
    }).toList();
  }

  Future<List<String>> adminFcmTokens() async {
    final results = await _runQuery({
      'structuredQuery': {
        'from': [
          {'collectionId': 'tokens', 'allDescendants': true},
        ],
        'limit': 500,
      },
    });

    final tokens = <String>{};
    for (final document in results) {
      final name = document['name'] as String? ?? '';
      if (!name.contains('/admin_fcm_tokens/')) continue;
      final fields = _decodeFields(document['fields'] as Map<String, dynamic>?);
      final token = fields['token'] as String?;
      if (token != null && token.isNotEmpty) tokens.add(token);
    }
    return tokens.toList();
  }

  Future<Map<String, dynamic>?> lookupUserByEmail(String email) async {
    final client = await _authClient();
    final response = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:lookup',
      ),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({
        'email': [email],
      }),
    );
    _throwIfBad(response, 'lookup Firebase Auth user');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final users = decoded['users'];
    if (users is List && users.isNotEmpty && users.first is Map) {
      return Map<String, dynamic>.from(users.first as Map);
    }
    return null;
  }

  Future<Map<String, dynamic>?> lookupUserByUid(String uid) async {
    final client = await _authClient();
    final response = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:lookup',
      ),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({
        'localId': [uid],
      }),
    );
    _throwIfBad(response, 'lookup Firebase Auth user');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final users = decoded['users'];
    if (users is List && users.isNotEmpty && users.first is Map) {
      return Map<String, dynamic>.from(users.first as Map);
    }
    return null;
  }

  Future<Map<String, dynamic>?> lookupUserByIdToken(String idToken) async {
    final client = await _authClient();
    final response = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:lookup',
      ),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
    if (response.statusCode == 400 || response.statusCode == 401) return null;
    _throwIfBad(response, 'verify Firebase Auth token');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final users = decoded['users'];
    if (users is List && users.isNotEmpty && users.first is Map) {
      return Map<String, dynamic>.from(users.first as Map);
    }
    return null;
  }

  Future<void> updateUserPassword(String uid, String password) async {
    final client = await _authClient();
    final response = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:update',
      ),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({'localId': uid, 'password': password}),
    );
    _throwIfBad(response, 'update Firebase Auth password');
  }

  Future<void> deleteAuthUser(String uid) async {
    final client = await _authClient();
    final response = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:delete',
      ),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({'localId': uid}),
    );
    _throwIfBad(response, 'delete Firebase Auth user');
  }

  Future<bool> sendFcm({
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    final client = await _authClient();
    final response = await client.post(
      Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      ),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({
        'message': {
          'token': token,
          'notification': {'title': title, 'body': body},
          'data': data,
          'android': {
            'priority': 'HIGH',
            'notification': {'channel_id': 'admin_safety_alerts'},
          },
        },
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return true;
    stderr.writeln('FCM send failed ${response.statusCode}: ${response.body}');
    return false;
  }

  Future<List<Map<String, dynamic>>> _runQuery(
    Map<String, dynamic> body,
  ) async {
    final client = await _authClient();
    final response = await client.post(
      Uri.parse('$_documentsBase:runQuery'),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode(body),
    );
    _throwIfBad(response, 'run Firestore query');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => row['document'])
        .whereType<Map>()
        .map((document) => Map<String, dynamic>.from(document))
        .toList();
  }

  String _relativePath(String fullName) {
    final marker = '/documents/';
    final index = fullName.indexOf(marker);
    return index < 0 ? fullName : fullName.substring(index + marker.length);
  }

  void _throwIfBad(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw _BadRequest(
      'Could not $action: ${response.statusCode} ${_shortError(response.body)}',
    );
  }
}

class _AdminAlertRecord {
  const _AdminAlertRecord({
    required this.id,
    required this.path,
    required this.data,
  });

  final String id;
  final String path;
  final Map<String, dynamic> data;
}

Map<String, dynamic> _encodeFields(Map<String, dynamic> data) {
  return {
    for (final entry in data.entries) entry.key: _encodeValue(entry.value),
  };
}

Map<String, dynamic> _encodeValue(Object? value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  if (value is num) return {'doubleValue': value.toDouble()};
  if (value is String) {
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value)) {
      return {'timestampValue': value};
    }
    return {'stringValue': value};
  }
  if (value is List) {
    return {
      'arrayValue': {'values': value.map(_encodeValue).toList()},
    };
  }
  if (value is Map) {
    return {
      'mapValue': {'fields': _encodeFields(Map<String, dynamic>.from(value))},
    };
  }
  return {'stringValue': value.toString()};
}

Map<String, dynamic> _decodeFields(Map<String, dynamic>? fields) {
  if (fields == null) return <String, dynamic>{};
  return {
    for (final entry in fields.entries) entry.key: _decodeValue(entry.value),
  };
}

Object? _decodeValue(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  if (raw.containsKey('stringValue')) return raw['stringValue'];
  if (raw.containsKey('integerValue')) {
    return int.tryParse(raw['integerValue'].toString());
  }
  if (raw.containsKey('doubleValue')) return _asDouble(raw['doubleValue']);
  if (raw.containsKey('booleanValue')) return raw['booleanValue'] == true;
  if (raw.containsKey('timestampValue')) return raw['timestampValue'];
  if (raw.containsKey('nullValue')) return null;
  if (raw['arrayValue'] is Map) {
    final values = (raw['arrayValue'] as Map)['values'];
    return values is List ? values.map(_decodeValue).toList() : const [];
  }
  if (raw['mapValue'] is Map) {
    final fields = (raw['mapValue'] as Map)['fields'];
    return _decodeFields(
      fields is Map<String, dynamic> ? fields : <String, dynamic>{},
    );
  }
  return null;
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

  @override
  String toString() => message;
}
