import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final TextEditingController _controller = TextEditingController();

  String selectedTag = "";

  final List<String> tags = [
    "Stress",
    "Happy",
    "Productive",
    "Tired",
    "Motivated",
  ];
  String currentPrompt = "";
  @override
  void initState() {
    super.initState();
    currentPrompt = _getPrompt();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.only(bottom: keyboard),

      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),

        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height - 120,
          ),

          child: Padding(
            padding: const EdgeInsets.all(20),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                // 🧠 PROMPT CARD
                Container(
                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),

                  child: Row(
                    children: [
                      const Text("🧠", style: TextStyle(fontSize: 24)),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          currentPrompt,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 📝 JOURNAL INPUT
                Container(
                  height: 320,

                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),

                  child: TextField(
                    controller: _controller,
                    maxLines: null,

                    decoration: const InputDecoration(
                      hintText: "Write your thoughts here...",
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 🏷 TAGS
                Wrap(
                  spacing: 8,
                  runSpacing: 8,

                  children: tags.map((tag) {
                    final isSelected = selectedTag == tag;

                    return ChoiceChip(
                      label: Text(tag),
                      selected: isSelected,

                      onSelected: (_) {
                        setState(() {
                          selectedTag = tag;
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // 💾 SAVE BUTTON
                SizedBox(
                  width: double.infinity,

                  child: ElevatedButton(
                    onPressed: _saveJournal,

                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),

                    child: const Text("Save Entry"),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getPrompt() {
    final prompts = [
      "What made today meaningful?",
      "What challenged you today?",
      "What are you grateful for?",
      "What drained your energy today?",
      "What did you learn today?",
    ];

    prompts.shuffle();
    return prompts.first;
  }

  Future<void> _saveJournal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final text = _controller.text.trim();

    if (text.isEmpty) {
      HapticFeedback.mediumImpact();

      final messenger = ScaffoldMessenger.of(context);

      messenger.clearSnackBars();

      messenger.showSnackBar(
        SnackBar(
          content: const Text("Please write something first"),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );

      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('journal')
          .add({
            'text': text,
            'tag': selectedTag,
            'prompt': currentPrompt,
            'created_at': FieldValue.serverTimestamp(),
          });

      debugPrint("Journal saved to Firestore");

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Journal saved")));

        _controller.clear();
        setState(() {
          selectedTag = "";
          currentPrompt = _getPrompt();
        });
      }
    } catch (e) {
      debugPrint("Error saving journal: $e");

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Failed to save journal")));
      }
    }
  }
}
