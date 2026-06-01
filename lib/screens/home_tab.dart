import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_data.dart';
import '../services/hometab_service.dart';
import '../services/journal_service.dart';
import '../services/moodscreen_service.dart';
import '../services/steps_service.dart';
import 'mood_popup_card.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await showDailyMotivation(context);
      if (!mounted) return;
      await showMoodPopupIfNeeded(context);
    });
  }

  Future<void> showDailyMotivation(BuildContext context) async {
    final data = context.read<AppData>();
    final quote = data.dailyQuote?["quote"] ?? "Keep going one step at a time.";
    final author = data.dailyQuote?["author"] ?? "Unknown";

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          backgroundColor: Colors.transparent,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                  color: const Color(0xFFFF7A59),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Daily Motivation",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.format_quote_rounded,
                        color: Colors.orange.shade300,
                        size: 34,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        quote,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF222222),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          author,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A59),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Continue",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================= DAILY MOOD POPUP =================

  Future<void> showMoodPopupIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    final today =
        "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";

    final lastShown = prefs.getString("last_mood_popup");

    if (lastShown == today) return;

    await prefs.setString("last_mood_popup", today);

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,

      builder: (_) => const MoodPopupCard(),
    );
  }

  Future<void> _refreshHome(AppData data) async {
    await Future.wait<void>([
      HomeTabService.preload(data),
      StepsService.instance.refreshNow(),
      MoodService.instance.loadTodayMood(),
    ]);
    unawaited(JournalService.initialize(data));
  }

  String _moodEmoji(int mood) {
    switch (mood) {
      case 0:
        return "\u{1F61E}";
      case 1:
        return "\u{1F642}";
      case 2:
        return "\u{1F604}";
      case 3:
        return "\u{1F929}";
      default:
        return "-";
    }
  }

  String moodIntensityLabel(double intensity) {
    if (intensity < 0.25) {
      return "Low";
    } else if (intensity < 0.5) {
      return "Moderate";
    } else if (intensity < 0.75) {
      return "High";
    } else {
      return "Super";
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();

    final progress = (data.stepsToday / data.stepGoal).clamp(0, 1.0);

    final remaining = (data.stepGoal - data.stepsToday).clamp(0, data.stepGoal);

    return SafeArea(
      child: RefreshIndicator(
        color: Colors.deepOrange,
        onRefresh: () => _refreshHome(data),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),

          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // ================= HERO CARD =================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),

                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.shade300,
                      Colors.deepOrange.shade400,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),

                  borderRadius: BorderRadius.circular(28),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withAlpha((0.25 * 255).round()),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),

                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.18 * 255).round()),
                            borderRadius: BorderRadius.circular(18),
                          ),

                          child: const Icon(
                            Icons.directions_walk_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),

                        const Spacer(),

                        if (progress > 0)
                          Text(
                            "${(progress * 100).toInt()}%",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      "Today's Progress",
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      "${data.stepsToday}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const Text(
                      "steps walked",
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),

                    const SizedBox(height: 18),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),

                      child: LinearProgressIndicator(
                        value: progress as double,
                        minHeight: 10,

                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      data.stepsToday >= data.stepGoal
                          ? "Goal completed \u{1F389}"
                          : "$remaining steps remaining to hit your goal",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ================= QUICK STATS =================
              Row(
                children: [
                  Expanded(
                    child: _miniCard(
                      icon: Icons.local_fire_department_rounded,
                      title: "Streak",
                      value: "${data.currentStreak}",
                      subtitle: "days",
                      color: Colors.deepOrange,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: _miniCard(
                      icon: Icons.mood_rounded,
                      title: "Mood",
                      value:
                          "${_moodEmoji(data.moodIndex)} ${moodIntensityLabel(data.moodIntensity)}",
                      subtitle: "today",
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _miniCard(
                      icon: Icons.trending_up_rounded,
                      title: "Trend",
                      value:
                          "${data.trendPercent >= 0 ? "+" : ""}${data.trendPercent.toStringAsFixed(1)}%",
                      subtitle: "this week",
                      color: Colors.green,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: _miniCard(
                      icon: Icons.flag_rounded,
                      title: "Goal",
                      value: "${data.stepGoal}",
                      subtitle: "daily target",
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ================= SMART MESSAGE =================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),

                decoration: BoxDecoration(
                  color: data.stepsToday >= data.stepGoal
                      ? Colors.green.shade50
                      : Colors.orange.shade50,

                  borderRadius: BorderRadius.circular(22),

                  border: Border.all(
                    color: data.stepsToday >= data.stepGoal
                        ? Colors.green.shade200
                        : Colors.orange.shade200,
                  ),
                ),

                child: Row(
                  children: [
                    Icon(
                      data.stepsToday >= data.stepGoal
                          ? Icons.emoji_events_rounded
                          : Icons.directions_walk_rounded,

                      color: data.stepsToday >= data.stepGoal
                          ? Colors.green
                          : Colors.deepOrange,

                      size: 30,
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Text(
                        data.stepsToday >= data.stepGoal
                            ? "Amazing work today! Keep the momentum going \u{1F389}"
                            : "A short walk can boost both your mood and productivity \u{1F6B6}",

                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w600,

                          color: data.stepsToday >= data.stepGoal
                              ? Colors.green.shade700
                              : Colors.deepOrange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= MINI CARD =================
  Widget _miniCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Container(
            padding: const EdgeInsets.all(10),

            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),

            child: Icon(icon, color: color, size: 22),
          ),

          const SizedBox(height: 14),

          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),

          const SizedBox(height: 4),

          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,

            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 2),

          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
