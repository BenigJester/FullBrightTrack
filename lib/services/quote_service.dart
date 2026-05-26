import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuoteService {
  static Future<Map<String, String>> getDailyQuote() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user!.uid;

    final today = DateTime.now().toIso8601String().split('T').first;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('daily_quote')
        .doc(today);

    final doc = await docRef.get();

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

      await docRef.set({
        ...quote,
        "date": today,
        "createdAt": FieldValue.serverTimestamp(),
      });

      return quote;
    } else {
      throw Exception("Failed to fetch quote");
    }
  }
}
