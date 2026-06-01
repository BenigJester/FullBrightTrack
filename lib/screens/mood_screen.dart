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
  Future<void> _refreshMood() async {
    await MoodService.instance.loadTodayMood();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final moodService = MoodService.instance;

    return RefreshIndicator(
      color: Colors.deepOrange,
      onRefresh: _refreshMood,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _MoodHero(
                      emoji: moodService.moods[data.selectedMood],
                      title: _moodTitle(data.selectedMood),
                      insight: moodService.getMoodInsight(),
                    ),
                    const SizedBox(height: 20),
                    _MoodSelector(data: data, moodService: moodService),
                    const SizedBox(height: 20),
                    _IntensityCard(data: data, moodService: moodService),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _moodTitle(int mood) {
    switch (mood) {
      case 0:
        return "Low mood";
      case 1:
        return "Calm";
      case 2:
        return "Positive";
      case 3:
        return "Energized";
      default:
        return "Mood check-in";
    }
  }
}

class _MoodHero extends StatelessWidget {
  const _MoodHero({
    required this.emoji,
    required this.title,
    required this.insight,
  });

  final String emoji;
  final String title;
  final String insight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF1EB), Color(0xFFFFE4D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Text(
              emoji,
              key: ValueKey(emoji),
              style: const TextStyle(fontSize: 78),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            insight,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MoodSelector extends StatelessWidget {
  const _MoodSelector({required this.data, required this.moodService});

  final AppData data;
  final MoodService moodService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "How are you feeling today?",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(moodService.moods.length, (index) {
              final selected = data.selectedMood == index;

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => moodService.updateMood(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.deepOrange.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    moodService.moods[index],
                    style: TextStyle(fontSize: selected ? 36 : 30),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _IntensityCard extends StatelessWidget {
  const _IntensityCard({required this.data, required this.moodService});

  final AppData data;
  final MoodService moodService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Mood intensity",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              Text(
                "${(data.moodIntensity * 100).toStringAsFixed(0)}%",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: data.moodIntensity,
            activeColor: Colors.deepOrange,
            inactiveColor: Colors.orange.shade100,
            onChanged: moodService.updateIntensity,
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}
