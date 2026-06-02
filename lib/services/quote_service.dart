import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuoteService {
  static const _fallbackQuote = {
    "quote": "Stay consistent. Small steps matter.",
    "author": "System",
  };

  static Future<Map<String, String>> getDailyQuote() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _fallbackQuote;

    final uid = user.uid;

    final today = DateTime.now().toIso8601String().split('T').first;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('daily_quote')
        .doc(today);

    final DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await docRef.get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return _fallbackQuote;
      }

      rethrow;
    }

    if (doc.exists) {
      return {"quote": doc['quote'], "author": doc['author']};
    }

    // Else -> fetch from API
    final response = await http.get(
      Uri.parse("https://zenquotes.io/api/random"),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      final quote = {
        "quote": data[0]["q"].toString(),
        "author": data[0]["a"].toString(),
      };

      try {
        await docRef.set({
          ...quote,
          "date": today,
          "createdAt": FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }

      return quote;
    } else {
      return _fallbackQuote;
    }
  }
}
