import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MoodJournalToggle extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onChanged;

  const MoodJournalToggle({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Stack(
        children: [
          // 🔥 SAFE ANIMATION (no layout conflict)
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: selectedIndex == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
            ),
          ),

          // 🔘 BUTTONS
          Row(children: [_buildItem("Mood", 0), _buildItem("Journal", 1)]),
        ],
      ),
    );
  }

  Widget _buildItem(String title, int index) {
    final isSelected = selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onChanged(index);
        },
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            child: Text(title),
          ),
        ),
      ),
    );
  }
}
