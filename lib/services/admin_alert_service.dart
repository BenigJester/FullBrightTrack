import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_navigator_service.dart';
import 'local_stress_model_service.dart';
import 'notification_history_service.dart';
import 'notification_service.dart';

class AdminAlertService {
  const AdminAlertService._();

  static final _firestore = FirebaseFirestore.instance;
  static final _seenAlertIds = <String>{};
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
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

  static Future<void> markResolvedForSignature({
    required String userId,
    required String warningSignature,
  }) async {
    if (warningSignature.isEmpty) return;

    await _firestore
        .collection('admin_alerts')
        .doc(_alertId(userId, warningSignature))
        .set({
          'status': 'resolved',
          'resolvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  static Future<void> startAdminAlertListener() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _subscription != null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.data()?['isAdmin'] != true) return;

    _subscription = _firestore
        .collection('admin_alerts')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(10)
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
                    createdAt: DateTime.now(),
                  ),
                ),
              );
              NotificationService.showAdminSafetyAlert(
                displayName: displayName,
                rank: rank,
              );
              _showInAppAlert(title: title, body: body);
            }
          },
          onError: (error) {
            debugPrint('Admin alert listener failed: $error');
          },
        );
  }

  static Future<void> stopAdminAlertListener() async {
    await _subscription?.cancel();
    _subscription = null;
    _seenAlertIds.clear();
    _listenerPrimed = false;
  }

  static void _showInAppAlert({required String title, required String body}) {
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Review'),
              ),
            ],
          );
        },
      );
    });
  }

  static String _alertId(String userId, String warningSignature) {
    final encoded = base64Url
        .encode(utf8.encode(warningSignature))
        .replaceAll('=', '');
    final safeLength = min(encoded.length, 90);
    return '${userId}_${encoded.substring(0, safeLength)}';
  }
}
