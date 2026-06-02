import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_data.dart';
import '../services/moodscreen_service.dart';

class MoodPopupCard extends StatefulWidget {
  const MoodPopupCard({super.key});

  @override
  State<MoodPopupCard> createState() => _MoodPopupCardState();
}

class _MoodPopupCardState extends State<MoodPopupCard> {
  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();

    final moodService = MoodService.instance;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),

      child: Container(
        padding: const EdgeInsets.all(24),

        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            // ================= HEADER =================
            Container(
              width: 70,
              height: 6,

              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(20),
              ),
            ),

            const SizedBox(height: 24),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),

              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },

              child: Text(
                moodService.moods[data.selectedMood],
                key: ValueKey(data.selectedMood),

                style: const TextStyle(fontSize: 82),
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              "How are you feeling today?",
              textAlign: TextAlign.center,

              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text(
              moodService.getMoodInsight(),

              textAlign: TextAlign.center,

              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),

            const SizedBox(height: 28),

            // ================= MOODS =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,

              children: List.generate(moodService.moods.length, (index) {
                final isSelected = data.selectedMood == index;

                return GestureDetector(
                  onTap: () {
                    context.read<AppData>().updateMoodData(
                      moodIndex: index,
                      moodIntensity: data.moodIntensity,
                    );
                    moodService.updateMood(index);
                  },

                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),

                    padding: const EdgeInsets.all(10),

                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.orange.withValues(alpha: 0.12)
                          : Colors.transparent,

                      borderRadius: BorderRadius.circular(18),
                    ),

                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 220),

                      scale: isSelected ? 1.35 : 1,

                      child: Opacity(
                        opacity: isSelected ? 1 : 0.45,

                        child: Text(
                          moodService.moods[index],
                          style: const TextStyle(fontSize: 34),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 28),

            // ================= INTENSITY =================
            Align(
              alignment: Alignment.centerLeft,

              child: Text(
                "Intensity",
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            Slider(
              value: data.moodIntensity,

              activeColor: Colors.deepOrange,
              inactiveColor: Colors.orange.shade100,

              onChanged: (value) {
                context.read<AppData>().updateMoodData(
                  moodIndex: data.selectedMood,
                  moodIntensity: value,
                );
                moodService.updateIntensity(value);
              },
            ),

            const SizedBox(height: 10),

            // ================= BUTTON =================
            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,

                  padding: const EdgeInsets.symmetric(vertical: 16),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),

                onPressed: () {
                  final navigator = Navigator.of(context);
                  final appData = context.read<AppData>();
                  unawaited(
                    moodService.saveMoodNow(appData).catchError((error) {
                      debugPrint('Mood save skipped: $error');
                    }),
                  );
                  navigator.pop();
                },

                child: const Text(
                  "Done",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
