import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/journal_warning_service.dart';
import '../services/wellness_signal_service.dart';
import '../services/moodscreen_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/app_data.dart';
import '../services/journal_service.dart';
import 'journal_history.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _promptController = TextEditingController();

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

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _promptController.text = _getPrompt();
  }

  @override
  void dispose() {
    _controller.dispose();
    _promptController.dispose();
    super.dispose();
  }

  // ================= JOURNAL HISTORY =================

  Future<void> _openJournalHistory() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const JournalHistoryScreen()),
    );
  }

  Future<void> _refreshJournal() async {
    final appData = context.read<AppData>();

    setState(() {
      _promptController.text = _getPrompt();
    });

    await JournalService.initialize(appData);
  }

  // ================= MAIN UI =================

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: backgroundColor,

      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'journal_history_fab',
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

        child: RefreshIndicator(
          color: primaryColor,
          onRefresh: _refreshJournal,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),

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
                            color: Colors.orange.withValues(alpha: 0.08),
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
                              "\u{1F9E0}",
                              style: TextStyle(fontSize: 24),
                            ),
                          ),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "Today's Reflection",
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: "Random reflection question",
                                      onPressed: _saving
                                          ? null
                                          : () {
                                              setState(() {
                                                _promptController.text =
                                                    _getPrompt();
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.shuffle_rounded,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 6),

                                TextField(
                                  controller: _promptController,
                                  enabled: !_saving,
                                  minLines: 1,
                                  maxLines: 3,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    height: 1.4,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: "Write a reflection question...",
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade500,
                                    ),
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
                            color: Colors.black.withValues(alpha: 0.03),
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
                        onPressed: _saving ? null : _saveJournal,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,

                          elevation: 0,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),

                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,

                          children: [
                            if (_saving)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            else
                              const Icon(Icons.favorite_rounded),

                            const SizedBox(width: 10),

                            Text(
                              _saving ? "Saving entry..." : "Save Entry",
                              style: const TextStyle(
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
      "What emotion stayed with you today?",
      "What helped you feel grounded today?",
      "What felt heavier than expected?",
      "What is one thing you handled well?",
      "What do you need more of tomorrow?",
      "What do you want to let go of tonight?",
      "What gave you energy today?",
      "What small win can you recognize?",
      "What thought kept coming back today?",
      "What would make tomorrow a little easier?",
      "Who or what supported you today?",
      "What boundary would help you this week?",
      "What made you feel calm, even briefly?",
      "What is one honest thing you can tell yourself?",
      "What part of today deserves kindness?",
    ];

    prompts.shuffle();

    return prompts.first;
  }

  // ================= SAVE JOURNAL =================

  void _showJournalMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _showJournalFeedbackDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(message, style: const TextStyle(height: 1.4)),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text("Done"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveJournal() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final text = _controller.text.trim();
    final prompt = _promptController.text.trim();

    if (text.isEmpty) {
      HapticFeedback.mediumImpact();
      _showJournalMessage("Write a few thoughts before saving.");

      return;
    }

    try {
      setState(() {
        _saving = true;
      });

      final warningSummary = JournalWarningService.analyze(text);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('journal')
          .add({
            'text': text,
            'tag': selectedTag,
            'prompt': prompt.isEmpty ? "Free reflection" : prompt,
            'warningSnippets': warningSummary.snippets,
            'warningFindings': warningSummary.toJsonList(),
            'journalWarningWeight': warningSummary.weight,
            'journalWarningSeverity': warningSummary.severity.name,
            'hasDangerWarning':
                warningSummary.severity == JournalWarningSeverity.critical,
            'created_at': FieldValue.serverTimestamp(),
          });
      await WellnessSignalService.publishCurrentUserSignals();
      await MoodService.instance.applyJournalMood(text);

      if (mounted) {
        await _showJournalFeedbackDialog(
          title: "Journal saved",
          message:
              "AI refreshed today's mood from your new journal entry and updated your wellness signals.",
          icon: Icons.check_circle_outline_rounded,
          color: Colors.green,
        );

        _controller.clear();

        setState(() {
          selectedTag = "";
          _promptController.text = _getPrompt();
        });
      }
    } catch (e) {
      debugPrint("Error saving journal: $e");

      if (mounted) {
        await _showJournalFeedbackDialog(
          title: "Could not save journal",
          message:
              "Please check your connection and try again. Your entry was not saved.",
          icon: Icons.error_outline_rounded,
          color: Colors.redAccent,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}
