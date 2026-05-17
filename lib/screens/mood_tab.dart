import 'package:flutter/material.dart';
import 'mood_screen.dart';
import 'journal_screen.dart';
import 'mood_journal_toggle.dart';

class MoodTab extends StatefulWidget {
  const MoodTab({super.key});

  @override
  State<MoodTab> createState() => _MoodTabState();
}

class _MoodTabState extends State<MoodTab> {
  int selectedIndex = 0;

  // ================= KEEP SCREENS ALIVE =================

  final List<Widget> _screens = const [MoodScreen(), JournalScreen()];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 16),

          // ================= TOGGLE =================
          MoodJournalToggle(
            selectedIndex: selectedIndex,
            onChanged: (index) {
              setState(() {
                selectedIndex = index;
              });
            },
          ),

          const SizedBox(height: 16),

          // ================= PERSISTENT SCREENS =================
          Expanded(
            child: IndexedStack(index: selectedIndex, children: _screens),
          ),
        ],
      ),
    );
  }
}
