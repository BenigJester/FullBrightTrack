import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_navigator_service.dart';
import 'admin_access_service.dart';
import 'display_name_service.dart';
import 'local_stress_model_service.dart';
import 'notification_history_service.dart';
import 'notification_service.dart';
import '../screens/admin_monitoring_screen.dart';

class AdminAlertService {
  const AdminAlertService._();

  static final _firestore = FirebaseFirestore.instance;
  static final _seenAlertIds = <String>{};
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  static StreamSubscription<RemoteMessage>? _messageOpenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  static bool _listenerPrimed = false;

  static Future<void> publishCriticalWarningAlert({
    required String userId,
    required String displayName,
    required String warningSignature,
    required StressModelResult modelResult,
  }) async {
    if (warningSignature.isEmpty) return;

    final alertId = _alertId(userId, warningSignature);

    await _firestore.collection('admin_alerts').doc(alertId).set({
      'userId': userId,
      'displayName': displayName,
      'type': 'critical_journal_warning',
      'severity': 'critical',
      'status': 'active',
      'warningSignature': warningSignature,
      'stressScore': modelResult.score,
      'stressRank': modelResult.rank,
      'message': 'A high-risk wellness signal needs review.',
      'privacyNote':
          'Open Admin Monitoring. Full journal text is not included.',
      'pushStatus': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> publishImmediateCriticalJournalWarning({
    required User user,
    required String warningSignature,
  }) {
    return publishCriticalWarningAlert(
      userId: user.uid,
      displayName: DisplayNameService.cleanForDisplay(
        user.displayName ?? user.email,
        fallback: 'Student',
      ),
      warningSignature: warningSignature,
      modelResult: const StressModelResult(
        score: 100,
        rank: 'High',
        confidence: 1,
        modelVersion: 'journal-warning-direct-v1',
        rationale: ['critical journal warning'],
      ),
    );
  }

  static Future<void> markResolvedForSignature({
    required String userId,
    required String warningSignature,
  }) async {
    if (warningSignature.isEmpty) return;

    try {
      final alertRef = _firestore
          .collection('admin_alerts')
          .doc(_alertId(userId, warningSignature));
      final alertSnapshot = await alertRef.get();
      if (!alertSnapshot.exists) {
        debugPrint('Admin alert resolve skipped: alert document not found');
        return;
      }

      await alertRef.update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (error.code == 'not-found' || error.code == 'permission-denied') {
        debugPrint('Admin alert resolve skipped: ${error.code}');
        return;
      }
      rethrow;
    }
  }

  static Future<void> startAdminAlertListener() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _subscription != null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!AdminAccessService.dataHasAdminAccess(userDoc.data())) return;
    await _startNotificationOpenHandler();

    _subscription = _firestore
        .collection('admin_alerts')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen(
          (snapshot) {
            if (!_listenerPrimed) {
              _seenAlertIds.addAll(snapshot.docs.map((doc) => doc.id));
              _listenerPrimed = true;
              return;
            }

            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.removed) continue;
              final alertId = change.doc.id;
              if (!_seenAlertIds.add(alertId)) continue;

              final data = change.doc.data() ?? <String, dynamic>{};
              final displayName = (data['displayName'] as String?) ?? 'Student';
              final rank = (data['stressRank'] as String?) ?? 'High';
              final userId = (data['userId'] as String?) ?? '';
              final title = 'Wellness signal needs review';
              final body =
                  '$displayName has a $rank stress signal. Open Admin Monitoring.';

              unawaited(
                NotificationHistoryService.add(
                  NotificationHistoryItem(
                    id: alertId,
                    title: title,
                    body: body,
                    type: 'admin_safety_alert',
                    userId: userId,
                    createdAt: DateTime.now(),
                  ),
                ),
              );
              NotificationService.showAdminSafetyAlert(
                displayName: displayName,
                rank: rank,
                userId: userId,
              );
              _showInAppAlert(title: title, body: body, userId: userId);
            }
          },
          onError: (error) {
            debugPrint('Admin alert listener failed: $error');
          },
        );
  }

  static Future<void> stopAdminAlertListener() async {
    await _subscription?.cancel();
    await _messageOpenSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    _subscription = null;
    _messageOpenSubscription = null;
    _foregroundMessageSubscription = null;
    _seenAlertIds.clear();
    _listenerPrimed = false;
  }

  static Future<void> _startNotificationOpenHandler() async {
    if (_messageOpenSubscription == null) {
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        _handleRemoteMessageOpen(initialMessage);
      }

      _messageOpenSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleRemoteMessageOpen,
      );
    }

    _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen(
      _handleForegroundRemoteMessage,
    );
  }

  static void _handleRemoteMessageOpen(RemoteMessage message) {
    if (message.data['type'] != 'admin_safety_alert') return;
    openAdminMonitoring(userId: message.data['userId']);
  }

  static void _handleForegroundRemoteMessage(RemoteMessage message) {
    final type = message.data['type'] as String?;
    if (type != 'admin_safety_alert' && type != 'admin_notification_test') {
      return;
    }

    final title =
        message.notification?.title ??
        message.data['title'] as String? ??
        'FullBrightTrack alert';
    final body =
        message.notification?.body ??
        message.data['body'] as String? ??
        'Admin notification delivery is working.';

    if (type == 'admin_notification_test') {
      unawaited(
        NotificationService.notifications.show(
          id: 201,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'admin_safety_alerts',
              'Admin Safety Alerts',
              channelDescription: 'Privacy-safe alerts for admin review',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        ),
      );
      return;
    }

    final userId = (message.data['userId'] as String?) ?? '';
    final displayName = (message.data['displayName'] as String?) ?? 'Student';
    final rank = (message.data['stressRank'] as String?) ?? 'High';

    unawaited(
      NotificationHistoryService.add(
        NotificationHistoryItem(
          id:
              message.messageId ??
              'remote_${DateTime.now().microsecondsSinceEpoch}',
          title: title,
          body: body,
          type: 'admin_safety_alert',
          userId: userId,
          createdAt: DateTime.now(),
        ),
      ),
    );
    unawaited(
      NotificationService.showAdminSafetyAlert(
        displayName: displayName,
        rank: rank,
        userId: userId,
      ),
    );
    _showInAppAlert(title: title, body: body, userId: userId);
  }

  static void _showInAppAlert({
    required String title,
    required String body,
    required String userId,
  }) {
    final context = AppNavigatorService.context;
    if (context == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentContext = AppNavigatorService.context;
      if (currentContext == null || !currentContext.mounted) return;

      showDialog<void>(
        context: currentContext,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title)),
              ],
            ),
            content: Text(
              '$body\n\nFull journal text is not included in this alert.',
              style: const TextStyle(height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Review'),
                onPressed: () {
                  Navigator.pop(context);
                  openAdminMonitoring(userId: userId);
                },
              ),
            ],
          );
        },
      );
    });
  }

  static void openAdminMonitoring({String? userId}) {
    final context = AppNavigatorService.context;
    if (context == null || !context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminMonitoringScreen(
          initialUserId: userId == null || userId.isEmpty ? null : userId,
          refreshOnOpen: true,
        ),
      ),
    );
  }

  static String _alertId(String userId, String warningSignature) {
    final encoded = base64Url
        .encode(utf8.encode(warningSignature))
        .replaceAll('=', '');
    final safeLength = min(encoded.length, 90);
    return '${userId}_${encoded.substring(0, safeLength)}';
  }
}
