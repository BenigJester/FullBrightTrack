import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Email Login
  Future<User?> login(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return result.user;
  }

  // Register
  Future<User?> register(String email, String password) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return result.user;
  }

  Future<User?> linkPasswordToCurrentUser(String email, String password) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );

    final result = await user.linkWithCredential(credential);
    return result.user;
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<bool> signInWithGoogle() async {
    try {
      // await _googleSignIn.disconnect();
      await _googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) return false;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      return true;
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      return false;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  static Future<void> refreshGoogleProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await user.reload();

    final refreshed = FirebaseAuth.instance.currentUser;
    if (refreshed == null) return;

    UserInfo? googleInfo;
    for (final info in refreshed.providerData) {
      if (info.providerId == 'google.com') {
        googleInfo = info;
        break;
      }
    }

    if (googleInfo == null) return;

    GoogleSignInAccount? googleAccount;
    try {
      googleAccount = await GoogleSignIn().signInSilently();
    } catch (_) {
      googleAccount = null;
    }

    final nextName =
        googleAccount?.displayName ??
        googleInfo.displayName ??
        refreshed.displayName;
    final nextPhoto =
        googleAccount?.photoUrl ?? googleInfo.photoURL ?? refreshed.photoURL;

    if (nextName != null && nextName != refreshed.displayName) {
      await refreshed.updateDisplayName(nextName);
    }

    if (nextPhoto != null && nextPhoto != refreshed.photoURL) {
      await refreshed.updatePhotoURL(nextPhoto);
    }

    await FirebaseFirestore.instance.collection('users').doc(refreshed.uid).set({
      'name': nextName,
      'email': refreshed.email,
      'photoUrl': nextPhoto,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
