import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/app_data.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final TextEditingController _controller = TextEditingController();

  static const primaryColor = Color(0xFFFF7A59);
  static const backgroundColor = Color(0xFFFFFBFA);
  static const textPrimary = Color(0xFF2D2D2D);

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

  // ================= JOURNAL HISTORY =================

  Future<void> _openJournalHistory() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,

      builder: (context) {
        final appData = context.watch<AppData>();

        final journals = appData.journals;

        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.6,
          maxChildSize: 0.95,

          expand: false,

          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: backgroundColor,

                borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
              ),

              child: Column(
                children: [
                  const SizedBox(height: 14),

                  // ================= HANDLE =================
                  Container(
                    width: 64,
                    height: 5,

                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ================= HEADER =================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),

                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),

                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFF1EB), Color(0xFFFFE3D9)],
                            ),

                            borderRadius: BorderRadius.circular(20),
                          ),

                          child: const Icon(
                            Icons.menu_book_rounded,
                            color: primaryColor,
                            size: 28,
                          ),
                        ),

                        const SizedBox(width: 16),

                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Text(
                                "Journal History",

                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,

                                  color: textPrimary,
                                ),
                              ),

                              SizedBox(height: 4),

                              Text(
                                "Reflect on your thoughts and progress",

                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ================= BODY =================
                  Expanded(
                    child: appData.journalLoading
                        ? const Center(child: CircularProgressIndicator())
                        : journals.isEmpty
                        // ================= EMPTY STATE =================
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 40,
                              ),

                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,

                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(26),

                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,

                                      shape: BoxShape.circle,
                                    ),

                                    child: Icon(
                                      Icons.auto_stories_rounded,
                                      size: 54,
                                      color: Colors.orange.shade300,
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  const Text(
                                    "No Journal Entries Yet",

                                    textAlign: TextAlign.center,

                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,

                                      color: textPrimary,
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  Text(
                                    "Start writing your thoughts, emotions, and reflections to build your personal wellbeing journey.",

                                    textAlign: TextAlign.center,

                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.6,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        // ================= JOURNAL LIST =================
                        : ListView.builder(
                            controller: scrollController,

                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 8,
                            ),

                            itemCount: journals.length,

                            itemBuilder: (context, index) {
                              final journal = journals[index];

                              final timestamp =
                                  journal['created_at'] as Timestamp?;

                              final date = timestamp?.toDate();

                              final tag = journal['tag'] ?? '';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 18),

                                padding: const EdgeInsets.all(20),

                                decoration: BoxDecoration(
                                  color: Colors.white,

                                  borderRadius: BorderRadius.circular(28),

                                  border: Border.all(
                                    color: Colors.orange.shade100,
                                  ),

                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),

                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),

                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [
                                    // ================= TOP =================
                                    Row(
                                      children: [
                                        if (tag.toString().isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),

                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFE2D8),

                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),

                                            child: Text(
                                              tag,

                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,

                                                color: primaryColor,
                                              ),
                                            ),
                                          ),

                                        const Spacer(),

                                        Text(
                                          date != null
                                              ? "${date.month}/${date.day}/${date.year}"
                                              : "",

                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 18),

                                    // ================= JOURNAL TEXT =================
                                    Text(
                                      journal['text'] ?? '',

                                      style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.8,
                                        color: textPrimary,
                                      ),
                                    ),

                                    // ================= PROMPT =================
                                    if ((journal['prompt'] ?? '')
                                        .toString()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 20),

                                      Container(
                                        padding: const EdgeInsets.all(16),

                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF6F2),

                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),

                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,

                                          children: [
                                            const Text(
                                              "🧠",
                                              style: TextStyle(fontSize: 18),
                                            ),

                                            const SizedBox(width: 10),

                                            Expanded(
                                              child: Text(
                                                journal['prompt'] ?? '',

                                                style: TextStyle(
                                                  fontSize: 13,

                                                  height: 1.6,

                                                  fontStyle: FontStyle.italic,

                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ================= MAIN UI =================

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: backgroundColor,

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openJournalHistory,

        backgroundColor: primaryColor,
        foregroundColor: Colors.white,

        elevation: 4,

        icon: const Icon(Icons.menu_book_rounded),

        label: const Text(
          "My Journals",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      body: AnimatedPadding(
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
                  const SizedBox(height: 20),

                  // ================= PROMPT CARD =================
                  Container(
                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFF1EB), Color(0xFFFFE5DC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),

                      borderRadius: BorderRadius.circular(26),

                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),

                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),

                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),

                          child: const Text(
                            "🧠",
                            style: TextStyle(fontSize: 24),
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Text(
                                "Today's Reflection",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 6),

                              Text(
                                currentPrompt,
                                style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ================= JOURNAL INPUT =================
                  Container(
                    height: 320,

                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      color: Colors.white,

                      borderRadius: BorderRadius.circular(28),

                      border: Border.all(
                        color: Colors.orange.shade100,
                        width: 1.2,
                      ),

                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),

                    child: TextField(
                      controller: _controller,
                      maxLines: null,

                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.7,
                        color: textPrimary,
                      ),

                      decoration: InputDecoration(
                        border: InputBorder.none,

                        hintText: "Write your thoughts here...",

                        hintStyle: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ================= TAGS =================
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,

                    children: tags.map((tag) {
                      final isSelected = selectedTag == tag;

                      return ChoiceChip(
                        label: Text(tag),

                        selected: isSelected,

                        selectedColor: const Color(0xFFFFD8CC),

                        backgroundColor: Colors.white,

                        side: BorderSide(
                          color: isSelected
                              ? primaryColor
                              : Colors.orange.shade100,
                        ),

                        labelStyle: TextStyle(
                          color: isSelected
                              ? primaryColor
                              : Colors.grey.shade700,

                          fontWeight: FontWeight.w600,
                        ),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),

                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),

                        onSelected: (_) {
                          setState(() {
                            selectedTag = tag;
                          });
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 28),

                  // ================= SAVE BUTTON =================
                  SizedBox(
                    width: double.infinity,
                    height: 58,

                    child: ElevatedButton(
                      onPressed: _saveJournal,

                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,

                        elevation: 0,

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),

                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,

                        children: [
                          Icon(Icons.favorite_rounded),

                          SizedBox(width: 10),

                          Text(
                            "Save Entry",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================= RANDOM PROMPTS =================

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

  // ================= SAVE JOURNAL =================

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
