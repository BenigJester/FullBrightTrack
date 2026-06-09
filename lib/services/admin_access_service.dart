import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAccessService {
  const AdminAccessService._();

  static Future<AdminAccessRole> currentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return AdminAccessRole.none;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    return roleFromData(doc.data());
  }

  static Future<bool> isCurrentUserAdmin() async {
    return (await currentUserRole()).hasAdminAccess;
  }

  static Future<bool> isCurrentUserDeveloper() async {
    return (await currentUserRole()) == AdminAccessRole.developer;
  }

  static AdminAccessRole roleFromData(Map<String, dynamic>? data) {
    if (data == null) return AdminAccessRole.none;
    final role = (data['role'] as String?)?.trim().toLowerCase();
    if (role == 'developer') return AdminAccessRole.developer;
    if (role == 'admin') return AdminAccessRole.admin;
    if (role == 'user') return AdminAccessRole.user;

    // Temporary compatibility for accounts created before the role field.
    if (data['isDeveloper'] == true) return AdminAccessRole.developer;
    if (data['isAdmin'] == true) return AdminAccessRole.admin;
    return AdminAccessRole.user;
  }

  static bool dataHasAdminAccess(Map<String, dynamic>? data) {
    return roleFromData(data).hasAdminAccess;
  }
}

enum AdminAccessRole { none, user, admin, developer }

extension AdminAccessRoleX on AdminAccessRole {
  bool get hasAdminAccess {
    return this == AdminAccessRole.admin || this == AdminAccessRole.developer;
  }

  String get badgeLabel {
    switch (this) {
      case AdminAccessRole.developer:
        return 'DEV';
      case AdminAccessRole.admin:
        return 'ADMIN';
      case AdminAccessRole.user:
        return '';
      case AdminAccessRole.none:
        return '';
    }
  }

  String get tooltip {
    switch (this) {
      case AdminAccessRole.developer:
        return 'Developer account';
      case AdminAccessRole.admin:
        return 'Admin account';
      case AdminAccessRole.user:
        return '';
      case AdminAccessRole.none:
        return '';
    }
  }
}
