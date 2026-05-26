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
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.orange.shade700),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Daily Motivation",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"$quote"',
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "- $author",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Continue"),
            ),
          ],
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
    await HomeTabService.preload(data);
    await StepsService.instance.refreshNow();
    await MoodService.instance.loadTodayMood();
    await JournalService.initialize(data);
  }

  String moodLabel(int mood) {
    switch (mood) {
      case 0:
        return "😞";
      case 1:
        return "🙂";
      case 2:
        return "😄";
      case 3:
        return "🤩";
      default:
        return "—";
    }
  }

  String moodIntensityLabel(double intensity) {
    if (intensity < 0.25) {
      return "Slightly";
    } else if (intensity < 0.5) {
      return "Somewhat";
    } else if (intensity < 0.75) {
      return "Quite";
    } else {
      return "Extremely";
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();

    debugPrint("MOOD TYPE: ${data.moodIndex.runtimeType}");
    debugPrint("MOOD VALUE: ${data.moodIndex}");

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
                  colors: [Colors.orange.shade300, Colors.deepOrange.shade400],
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
                        ? "Goal completed 🎉"
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
                        "${moodLabel(data.moodIndex)} ${moodIntensityLabel(data.moodIntensity)}",
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
                          ? "Amazing work today! Keep the momentum going 🎉"
                          : "A short walk can boost both your mood and productivity 🚶",

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
