import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_data.dart';
import '../services/moodscreen_service.dart';

class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key});

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();

    final moodService = MoodService.instance;

    return RefreshIndicator(
      color: Colors.deepOrange,
      onRefresh: moodService.loadTodayMood,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
              child: Column(
                children: [
                  const SizedBox(height: 20),

          // ================= BIG EMOJI =================
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Text(
              moodService.moods[data.selectedMood],
              key: ValueKey(data.selectedMood),
              style: const TextStyle(fontSize: 80),
            ),
          ),

          const SizedBox(height: 10),

          const Text(
            "How are you feeling today?",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),

          const SizedBox(height: 30),

          // ================= MOOD SELECTOR =================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(moodService.moods.length, (index) {
              final isSelected = data.selectedMood == index;

              return GestureDetector(
                onTap: () {
                  moodService.updateMood(index);
                },
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: isSelected ? 1.5 : 1.0,
                  child: Opacity(
                    opacity: isSelected ? 1 : 0.5,
                    child: Text(
                      moodService.moods[index],
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 30),

          // ================= INTENSITY =================
          Column(
            children: [
              const Text("Intensity"),

              Slider(
                value: data.moodIntensity,
                activeColor: Colors.deepOrange,
                inactiveColor: Colors.orange.shade100,
                onChanged: (newValue) {
                  setState(() {
                    data.moodIntensity = newValue;
                  });
                },
                onChangeEnd: (value) {
                  moodService.updateIntensity(value);
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ================= INSIGHT =================
                  Text(
                    moodService.getMoodInsight(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
