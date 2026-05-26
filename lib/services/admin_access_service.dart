import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAccessService {
  const AdminAccessService._();

  static Future<bool> isCurrentUserAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data();
    if (data == null) return false;

    return data['isAdmin'] == true;
  }
}
