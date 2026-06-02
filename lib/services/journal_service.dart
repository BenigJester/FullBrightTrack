import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/app_data.dart';
import 'journal_warning_service.dart';
import 'wellness_signal_service.dart';
import 'moodscreen_service.dart';

class JournalService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static StreamSubscription? _journalSubscription;

  static User? get currentUser => _auth.currentUser;

  // =========================================================
  // COLLECTION
  // =========================================================

  static CollectionReference<Map<String, dynamic>> _journalCollection(
    String uid,
  ) {
    return _firestore.collection('users').doc(uid).collection('journal');
  }

  // =========================================================
  // INITIALIZE LISTENER
  // =========================================================

  static Future<void> initialize(AppData appData) async {
    final user = currentUser;

    if (user == null) return;

    appData.updateJournalData(journalList: [], loading: true);

    await _journalSubscription?.cancel();

    _journalSubscription = _journalCollection(user.uid)
        .orderBy('created_at', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final journals = snapshot.docs.map((doc) {
              final data = doc.data();

              return {'id': doc.id, ...data};
            }).toList();

            appData.updateJournalData(journalList: journals, loading: false);
          },
          onError: (Object error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              debugPrint('Journal listener skipped: permission-denied');
              appData.updateJournalData(journalList: const [], loading: false);
              return;
            }

            debugPrint('Journal listener failed: $error');
            appData.updateJournalData(journalList: const [], loading: false);
          },
        );
  }

  // =========================================================
  // SAVE JOURNAL
  // =========================================================

  static Future<void> saveJournal({
    required String text,
    required String tag,
    required String prompt,
  }) async {
    final user = currentUser;

    if (user == null) return;

    final warningSummary = JournalWarningService.analyze(text);

    await _journalCollection(user.uid).add({
      'text': text,
      'tag': tag,
      'prompt': prompt,
      'warningSnippets': warningSummary.snippets,
      'warningFindings': warningSummary.toJsonList(),
      'journalWarningWeight': warningSummary.weight,
      'journalWarningSeverity': warningSummary.severity.name,
      'hasDangerWarning':
          warningSummary.severity == JournalWarningSeverity.critical,
      'created_at': FieldValue.serverTimestamp(),
    });
    await WellnessSignalService.publishCurrentUserSignals();
    await MoodService.instance.applyJournalMood(text);
  }

  // =========================================================
  // DELETE
  // =========================================================

  static Future<void> deleteJournal(String journalId) async {
    final user = currentUser;

    if (user == null) return;

    await _journalCollection(user.uid).doc(journalId).delete();
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  static Future<void> dispose() async {
    await _journalSubscription?.cancel();
  }
}
