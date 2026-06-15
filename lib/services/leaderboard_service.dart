import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'display_name_service.dart';

class LeaderboardEntry {
  LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.monthlySteps,
    required this.todaySteps,
    required this.stepStreak,
    required this.moodStreak,
    required this.streakPoints,
    required this.rank,
    required this.isCurrentUser,
    required this.role,
    required this.sourceDocumentId,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final int monthlySteps;
  final int todaySteps;
  final int stepStreak;
  final int moodStreak;
  final int streakPoints;
  final int rank;
  final bool isCurrentUser;
  final String role;
  final String sourceDocumentId;

  LeaderboardEntry copyWith({int? rank}) {
    return LeaderboardEntry(
      uid: uid,
      name: name,
      photoUrl: photoUrl,
      monthlySteps: monthlySteps,
      todaySteps: todaySteps,
      stepStreak: stepStreak,
      moodStreak: moodStreak,
      streakPoints: streakPoints,
      rank: rank ?? this.rank,
      isCurrentUser: isCurrentUser,
      role: role,
      sourceDocumentId: sourceDocumentId,
    );
  }
}

class LeaderboardResult {
  LeaderboardResult({
    required this.entries,
    required this.currentUser,
    required this.monthLabel,
    required this.totalCount,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardEntry? currentUser;
  final String monthLabel;
  final int totalCount;

  List<LeaderboardEntry> get podium => entries.take(3).toList();
}

class LeaderboardService {
  static const int stepGoal = 4000;
  static const _cacheTtl = Duration(seconds: 45);

  static final _firestore = FirebaseFirestore.instance;
  static LeaderboardResult? _cachedResult;
  static DateTime? _cachedAt;

  static Future<LeaderboardResult> loadMonthlyLeaderboard({
    bool forceRefresh = false,
  }) async {
    final cached = _cachedResult;
    final cachedAt = _cachedAt;
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final monthKey = _monthKey(now);

    final docs = await _firestore.collection('leaderboard').get();
    final entries = <LeaderboardEntry>[];
    final staleCurrentUserDocs = <String>[];

    for (final doc in docs.docs) {
      final data = doc.data();
      if (data['monthKey'] != monthKey) continue;
      final canonicalUid = _canonicalUid(doc);
      if (currentUser != null &&
          canonicalUid == currentUser.uid &&
          doc.id != currentUser.uid) {
        staleCurrentUserDocs.add(doc.id);
      }

      final entry = await _entryFromDoc(doc, currentUser?.uid);
      if (entry != null) {
        entries.add(entry);
      }
    }

    if (staleCurrentUserDocs.isNotEmpty) {
      _cleanupStaleCurrentUserLeaderboardDocs(staleCurrentUserDocs);
    }

    final deduped = _dedupeByCanonicalUser(entries);

    deduped.sort((a, b) {
      final pointsCompare = b.streakPoints.compareTo(a.streakPoints);
      if (pointsCompare != 0) return pointsCompare;

      final stepStreakCompare = b.stepStreak.compareTo(a.stepStreak);
      if (stepStreakCompare != 0) return stepStreakCompare;

      final moodStreakCompare = b.moodStreak.compareTo(a.moodStreak);
      if (moodStreakCompare != 0) return moodStreakCompare;

      final stepsCompare = b.monthlySteps.compareTo(a.monthlySteps);
      if (stepsCompare != 0) return stepsCompare;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final ranked = <LeaderboardEntry>[];
    for (var index = 0; index < deduped.length; index++) {
      ranked.add(deduped[index].copyWith(rank: index + 1));
    }

    LeaderboardEntry? current;
    for (final entry in ranked) {
      if (entry.isCurrentUser) {
        current = entry;
        break;
      }
    }

    final result = LeaderboardResult(
      entries: ranked,
      currentUser: current,
      monthLabel: _monthLabel(now),
      totalCount: ranked.length,
    );
    _cachedResult = result;
    _cachedAt = DateTime.now();
    return result;
  }

  static Future<void> publishCurrentUserSummary({
    required int todaySteps,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final steps = await _loadUserMonthSteps(
      uid: user.uid,
      startKey: _dateKey(monthStart),
      endKey: _dateKey(monthEnd),
    );
    final mood = await _loadUserRecentMood(uid: user.uid, days: 30);

    steps[_dateKey(now)] = maxOf(steps[_dateKey(now)] ?? 0, todaySteps);

    final profile = await _firestore.collection('users').doc(user.uid).get();
    final profileData = profile.data() ?? <String, dynamic>{};
    final monthlySteps = steps.values.fold<int>(
      0,
      (total, value) => total + value,
    );
    final stepStreak = _currentStepStreak(steps, now);
    final moodStreak = _currentMoodStreak(mood, now);
    final streakPoints = stepStreak + moodStreak;

    await _firestore.collection('leaderboard').doc(user.uid).set({
      'uid': user.uid,
      'name': _firstName(_displayName(profileData)),
      'photoUrl': _photoUrl(profileData),
      'monthlySteps': monthlySteps,
      'todaySteps': steps[_dateKey(now)] ?? todaySteps,
      'currentStreak': stepStreak,
      'stepStreak': stepStreak,
      'moodStreak': moodStreak,
      'streakPoints': streakPoints,
      'role': _role(profileData),
      'monthKey': _monthKey(now),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<LeaderboardEntry?> _entryFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String? currentUid,
  ) async {
    final data = doc.data();
    final uid = _canonicalUid(doc);
    var profileData = <String, dynamic>{};
    try {
      final profile = await _firestore.collection('users').doc(uid).get();
      profileData = profile.data() ?? <String, dynamic>{};
    } catch (_) {
      profileData = <String, dynamic>{};
    }

    final monthlySteps = (data['monthlySteps'] as num?)?.toInt() ?? 0;
    final todaySteps = (data['todaySteps'] as num?)?.toInt() ?? 0;
    final stepStreak =
        (data['stepStreak'] as num?)?.toInt() ??
        (data['currentStreak'] as num?)?.toInt() ??
        0;
    final moodStreak = (data['moodStreak'] as num?)?.toInt() ?? 0;
    final streakPoints =
        (data['streakPoints'] as num?)?.toInt() ?? stepStreak + moodStreak;

    if (streakPoints == 0) {
      return null;
    }

    return LeaderboardEntry(
      uid: uid,
      name: _firstName(_displayName({...data, ...profileData})),
      photoUrl: _photoUrl({...data, ...profileData}),
      monthlySteps: monthlySteps,
      todaySteps: todaySteps,
      stepStreak: stepStreak,
      moodStreak: moodStreak,
      streakPoints: streakPoints,
      rank: 0,
      isCurrentUser: uid == currentUid,
      role: _role({...data, ...profileData}),
      sourceDocumentId: doc.id,
    );
  }

  static List<LeaderboardEntry> _dedupeByCanonicalUser(
    List<LeaderboardEntry> entries,
  ) {
    final byUid = <String, LeaderboardEntry>{};

    for (final entry in entries) {
      final current = byUid[entry.uid];
      if (current == null || _preferEntry(entry, current)) {
        byUid[entry.uid] = entry;
      }
    }

    return byUid.values.toList();
  }

  static bool _preferEntry(
    LeaderboardEntry candidate,
    LeaderboardEntry current,
  ) {
    final candidateUsesCanonicalDoc =
        candidate.sourceDocumentId == candidate.uid;
    final currentUsesCanonicalDoc = current.sourceDocumentId == current.uid;
    if (candidateUsesCanonicalDoc != currentUsesCanonicalDoc) {
      return candidateUsesCanonicalDoc;
    }

    if (candidate.streakPoints != current.streakPoints) {
      return candidate.streakPoints > current.streakPoints;
    }

    return candidate.monthlySteps > current.monthlySteps;
  }

  static String _canonicalUid(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final storedUid = (doc.data()['uid'] as String?)?.trim();
    return storedUid == null || storedUid.isEmpty ? doc.id : storedUid;
  }

  static void _cleanupStaleCurrentUserLeaderboardDocs(List<String> docIds) {
    for (final docId in docIds) {
      _firestore
          .collection('leaderboard')
          .doc(docId)
          .delete()
          .catchError((_) {});
    }
  }

  static Future<Map<String, int>> _loadUserMonthSteps({
    required String uid,
    required String startKey,
    required String endKey,
  }) async {
    final docs = await _firestore
        .collection('users')
        .doc(uid)
        .collection('steps')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .orderBy(FieldPath.documentId)
        .get();

    return {
      for (final doc in docs.docs)
        doc.id: (doc.data()['steps'] as num?)?.toInt() ?? 0,
    };
  }

  static Future<Map<String, int?>> _loadUserRecentMood({
    required String uid,
    required int days,
  }) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days - 1));

    final dates = List.generate(days, (index) {
      final date = start.add(Duration(days: index));
      return _dateKey(date);
    });

    final docs = await _firestore
        .collection('users')
        .doc(uid)
        .collection('mood')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: dates.first)
        .where(FieldPath.documentId, isLessThanOrEqualTo: dates.last)
        .orderBy(FieldPath.documentId)
        .get();

    final result = <String, int?>{for (final date in dates) date: null};

    for (final doc in docs.docs) {
      result[doc.id] = (doc.data()['mood_index'] as num?)?.toInt();
    }

    return result;
  }

  static int _currentStepStreak(Map<String, int> steps, DateTime now) {
    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    final todayKey = _dateKey(cursor);

    if ((steps[todayKey] ?? 0) < stepGoal) {
      cursor = cursor.subtract(const Duration(days: 1));
    }

    while (!cursor.isBefore(DateTime(now.year, now.month, 1))) {
      final key = _dateKey(cursor);
      if ((steps[key] ?? 0) < stepGoal) break;

      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  static int _currentMoodStreak(Map<String, int?> mood, DateTime now) {
    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    final todayKey = _dateKey(cursor);

    if (mood[todayKey] == null) {
      cursor = cursor.subtract(const Duration(days: 1));
    }

    while (!cursor.isBefore(DateTime(now.year, now.month, 1))) {
      final key = _dateKey(cursor);
      if (mood[key] == null) break;

      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  static String _displayName(Map<String, dynamic> data) {
    final name = DisplayNameService.normalize(data['name'] as String?);
    if (name.isNotEmpty) return name;

    final email = DisplayNameService.normalize(data['email'] as String?);
    if (email.isNotEmpty) return email.split('@').first;

    return 'Student';
  }

  static String? _photoUrl(Map<String, dynamic> data) {
    final photoUrl = (data['photoUrl'] as String?)?.trim();
    return photoUrl == null || photoUrl.isEmpty ? null : photoUrl;
  }

  static String _role(Map<String, dynamic> data) {
    final role = (data['role'] as String?)?.trim().toLowerCase();
    if (role == 'developer' || role == 'admin') return role!;
    if (data['isDeveloper'] == true) return 'developer';
    if (data['isAdmin'] == true) return 'admin';
    return 'user';
  }

  static String _firstName(String name) {
    return DisplayNameService.firstName(name, fallback: 'Student');
  }

  static String _dateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  static String _monthKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}";
  }

  static int maxOf(int a, int b) => a > b ? a : b;

  static String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.year}';
  }
}
