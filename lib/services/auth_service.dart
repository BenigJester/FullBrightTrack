import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'display_name_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static String? lastGoogleSignInError;

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

  Future<User?> linkGoogleToCurrentUser({
    bool forceAccountSelection = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    lastGoogleSignInError = null;
    try {
      if (forceAccountSelection) {
        try {
          await _googleSignIn.disconnect();
        } catch (_) {
          await _googleSignIn.signOut();
        }
      }

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        lastGoogleSignInError = 'Google sign-in was cancelled by the user.';
        return null;
      }

      if (user.email != null &&
          googleUser.email.toLowerCase() != user.email!.toLowerCase()) {
        await _googleSignIn.signOut();
        throw FirebaseAuthException(
          code: 'email-mismatch',
          message:
              'Please choose the Google account that uses ${user.email}.',
        );
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await user.linkWithCredential(credential);
      return result.user;
    } catch (e) {
      lastGoogleSignInError = e.toString();
      debugPrint("Google link error: $e");
      rethrow;
    }
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<bool> signInWithGoogle({bool forceAccountSelection = true}) async {
    lastGoogleSignInError = null;
    try {
      if (forceAccountSelection) {
        try {
          await _googleSignIn.disconnect();
        } catch (_) {
          await _googleSignIn.signOut();
        }
      } else {
        await _googleSignIn.signOut();
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        lastGoogleSignInError = 'Google sign-in was cancelled by the user.';
        return false;
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      return true;
    } catch (e) {
      lastGoogleSignInError = e.toString();
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

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(refreshed.uid);
    final userDoc = await userRef.get();

    if (userDoc.exists) {
      final data = userDoc.data();
      final savedName = DisplayNameService.normalize(data?['name'] as String?);
      final savedPhoto = (data?['photoUrl'] as String?)?.trim();

      if (savedName.isNotEmpty && savedName != refreshed.displayName) {
        await refreshed.updateDisplayName(savedName);
      }

      if (savedPhoto != null &&
          savedPhoto.isNotEmpty &&
          savedPhoto != refreshed.photoURL) {
        await refreshed.updatePhotoURL(savedPhoto);
      }

      await userRef.set({
        'email': refreshed.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return;
    }

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

    final nextName = DisplayNameService.cleanForDisplay(
      googleAccount?.displayName ??
          googleInfo.displayName ??
          refreshed.displayName,
      fallback: 'User',
    );
    final nextPhoto =
        googleAccount?.photoUrl ?? googleInfo.photoURL ?? refreshed.photoURL;

    if (nextName != refreshed.displayName) {
      await refreshed.updateDisplayName(nextName);
    }

    if (nextPhoto != null && nextPhoto != refreshed.photoURL) {
      await refreshed.updatePhotoURL(nextPhoto);
    }

    await userRef.set({
      'name': nextName,
      'email': refreshed.email,
      'photoUrl': nextPhoto,
      'role': 'user',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
