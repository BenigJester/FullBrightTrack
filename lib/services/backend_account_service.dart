import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendAccountService {
  const BackendAccountService._();

  static const _configuredBackendUrl = String.fromEnvironment(
    'FULLBRIGHT_BACKEND_URL',
  );
  static const _configuredStressUrl = String.fromEnvironment(
    'GENKIT_STRESS_FLOW_URL',
  );
  static const _debugBackendUrl = String.fromEnvironment(
    'FULLBRIGHT_BACKEND_DEBUG_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static String get _baseUrl {
    final configuredBackend = _configuredBackendUrl.trim();
    if (configuredBackend.isNotEmpty) {
      return configuredBackend.replaceAll(RegExp(r'/+$'), '');
    }

    final stressUrl = _configuredStressUrl.trim();
    if (stressUrl.isNotEmpty) {
      final uri = Uri.tryParse(stressUrl);
      if (uri != null) {
        final segments = uri.pathSegments.where((part) => part != 'stress');
        return uri
            .replace(pathSegments: segments, query: '', fragment: '')
            .toString()
            .replaceAll(RegExp(r'/+$'), '');
      }
    }

    return kReleaseMode ? '' : _debugBackendUrl.trim();
  }

  static bool get isConfigured => _baseUrl.isNotEmpty;

  static Future<PendingRegistrationResult> startRegistration({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) {
      throw const BackendAccountException(
        'Account confirmation backend is not configured.',
      );
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/start-registration'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 35));

    final decoded = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (data['error'] as String?)?.trim();
      throw BackendAccountException(
        message == null || message.isEmpty
            ? 'Could not start registration confirmation.'
            : message,
      );
    }

    return PendingRegistrationResult(
      email: (data['email'] as String?) ?? email,
      requestId: (data['requestId'] as String?) ?? '',
      confirmationUrl: (data['confirmationUrl'] as String?) ?? '',
      expiresAt: DateTime.tryParse((data['expiresAt'] as String?) ?? ''),
    );
  }

  static Future<PasswordResetRequestResult> requestPasswordReset({
    required String email,
  }) async {
    if (!isConfigured) {
      throw const BackendAccountException(
        'Password reset backend is not configured.',
      );
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/request-password-reset'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 25));

    final decoded = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (data['error'] as String?)?.trim();
      throw BackendAccountException(
        message == null || message.isEmpty
            ? 'Could not request password reset.'
            : message,
      );
    }

    return PasswordResetRequestResult(
      email: (data['email'] as String?) ?? email,
      requestId: (data['requestId'] as String?) ?? '',
      resetUrl: (data['resetUrl'] as String?) ?? '',
      expiresAt: DateTime.tryParse((data['expiresAt'] as String?) ?? ''),
    );
  }
}

class PendingRegistrationResult {
  const PendingRegistrationResult({
    required this.email,
    required this.requestId,
    required this.confirmationUrl,
    required this.expiresAt,
  });

  final String email;
  final String requestId;
  final String confirmationUrl;
  final DateTime? expiresAt;
}

class PasswordResetRequestResult {
  const PasswordResetRequestResult({
    required this.email,
    required this.requestId,
    required this.resetUrl,
    required this.expiresAt,
  });

  final String email;
  final String requestId;
  final String resetUrl;
  final DateTime? expiresAt;
}

class BackendAccountException implements Exception {
  const BackendAccountException(this.message);

  final String message;

  @override
  String toString() => message;
}
