import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LeaderboardEntry {
  LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.monthlySteps,
    required this.todaySteps,
    required this.currentStreak,
    required this.rank,
    required this.isCurrentUser,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final int monthlySteps;
  final int todaySteps;
  final int currentStreak;
  final int rank;
  final bool isCurrentUser;

  LeaderboardEntry copyWith({int? rank}) {
    return LeaderboardEntry(
      uid: uid,
      name: name,
      photoUrl: photoUrl,
      monthlySteps: monthlySteps,
      todaySteps: todaySteps,
      currentStreak: currentStreak,
      rank: rank ?? this.rank,
      isCurrentUser: isCurrentUser,
    );
  }
}

class LeaderboardResult {
  LeaderboardResult({
    required this.entries,
    required this.currentUser,
    required this.monthLabel,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardEntry? currentUser;
  final String monthLabel;

  List<LeaderboardEntry> get podium => entries.take(3).toList();
}

class LeaderboardService {
  static const int stepGoal = 4000;

  static final _firestore = FirebaseFirestore.instance;

  static Future<LeaderboardResult> loadMonthlyLeaderboard({
    int limit = 30,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final monthKey = _monthKey(now);

    final docs = await _firestore.collection('leaderboard').get();
    final entries = <LeaderboardEntry>[];

    for (final doc in docs.docs) {
      final data = doc.data();
      if (data['monthKey'] != monthKey) continue;

      final entry = _entryFromDoc(doc, currentUser?.uid);
      if (entry != null) {
        entries.add(entry);
      }
    }

    entries.sort((a, b) {
      final stepsCompare = b.monthlySteps.compareTo(a.monthlySteps);
      if (stepsCompare != 0) return stepsCompare;

      final streakCompare = b.currentStreak.compareTo(a.currentStreak);
      if (streakCompare != 0) return streakCompare;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final ranked = <LeaderboardEntry>[];
    for (var index = 0; index < entries.length; index++) {
      ranked.add(entries[index].copyWith(rank: index + 1));
    }

    LeaderboardEntry? current;
    for (final entry in ranked) {
      if (entry.isCurrentUser) {
        current = entry;
        break;
      }
    }

    return LeaderboardResult(
      entries: ranked.take(limit).toList(),
      currentUser: current,
      monthLabel: _monthLabel(now),
    );
  }

  static Future<void> publishCurrentUserSummary({required int todaySteps}) async {
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

    steps[_dateKey(now)] = maxOf(steps[_dateKey(now)] ?? 0, todaySteps);

    final profile = await _firestore.collection('users').doc(user.uid).get();
    final profileData = profile.data() ?? <String, dynamic>{};
    final monthlySteps = steps.values.fold<int>(
      0,
      (total, value) => total + value,
    );

    await _firestore.collection('leaderboard').doc(user.uid).set({
      'uid': user.uid,
      'name': _firstName(
        _displayName({
          ...profileData,
          'name': profileData['name'] ?? user.displayName,
          'email': profileData['email'] ?? user.email,
        }),
      ),
      'photoUrl': profileData['photoUrl'] ?? user.photoURL,
      'monthlySteps': monthlySteps,
      'todaySteps': steps[_dateKey(now)] ?? todaySteps,
      'currentStreak': _currentStreak(steps, now),
      'monthKey': _monthKey(now),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static LeaderboardEntry? _entryFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String? currentUid,
  ) {
    final data = doc.data();
    final monthlySteps = (data['monthlySteps'] as num?)?.toInt() ?? 0;
    final todaySteps = (data['todaySteps'] as num?)?.toInt() ?? 0;
    final currentStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;

    if (monthlySteps == 0 && todaySteps == 0 && currentStreak == 0) {
      return null;
    }

    return LeaderboardEntry(
      uid: doc.id,
      name: _firstName(_displayName(data)),
      photoUrl: data['photoUrl'] as String?,
      monthlySteps: monthlySteps,
      todaySteps: todaySteps,
      currentStreak: currentStreak,
      rank: 0,
      isCurrentUser: doc.id == currentUid,
    );
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

  static int _currentStreak(Map<String, int> steps, DateTime now) {
    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);

    while (cursor.month == now.month) {
      final key = _dateKey(cursor);
      if ((steps[key] ?? 0) < stepGoal) break;

      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  static String _displayName(Map<String, dynamic> data) {
    final name = (data['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;

    final email = (data['email'] as String?)?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;

    return 'Student';
  }

  static String _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Student';

    return trimmed.split(RegExp(r'\s+')).first;
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
