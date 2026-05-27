import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationHistoryService {
  const NotificationHistoryService._();

  static const _maxItems = 50;

  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static Future<List<NotificationHistoryItem>> load() async {
    final collection = await _adminHistoryCollection();
    if (collection == null) return const [];

    final snapshot = await collection
        .orderBy('createdAt', descending: true)
        .limit(_maxItems)
        .get();

    return snapshot.docs
        .map((doc) => NotificationHistoryItem.fromFirestore(doc))
        .toList();
  }

  static Future<void> add(NotificationHistoryItem item) async {
    final collection = await _adminHistoryCollection();
    if (collection == null) return;

    await collection.doc(item.id).set({
      'title': item.title,
      'body': item.body,
      'type': item.type,
      'createdAt': Timestamp.fromDate(item.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> delete(String id) async {
    final collection = await _adminHistoryCollection();
    if (collection == null) return;

    await collection.doc(id).delete();
  }

  static Future<void> clearAll() async {
    final collection = await _adminHistoryCollection();
    if (collection == null) return;

    final snapshot = await collection.limit(_maxItems).get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  static Future<CollectionReference<Map<String, dynamic>>?>
  _adminHistoryCollection() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.data()?['isAdmin'] != true) return null;

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('notification_history');
  }
}

class NotificationHistoryItem {
  const NotificationHistoryItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;

  factory NotificationHistoryItem.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];

    return NotificationHistoryItem(
      id: doc.id,
      title: data['title'] as String? ?? 'Notification',
      body: data['body'] as String? ?? '',
      type: data['type'] as String? ?? 'general',
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
