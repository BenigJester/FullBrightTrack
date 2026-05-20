import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../models/app_data.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

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

    logServiceStatus();

    final progress = (data.stepsToday / data.stepGoal).clamp(0, 1.0);

    final remaining = (data.stepGoal - data.stepsToday).clamp(0, data.stepGoal);

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),

        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            _glassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.orange.shade700,
                      ),

                      const SizedBox(width: 8),

                      const Text(
                        "Daily Motivation",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Text(
                    '"${data.dailyQuote?["quote"] ?? "Keep going one step at a time."}"',
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Align(
                    alignment: Alignment.bottomRight,

                    child: Text(
                      "- ${data.dailyQuote?["author"] ?? "Unknown"}",
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

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

  // ================= GLASS CARD =================

  Widget _glassCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: child,
    );
  }
}

Future<void> logServiceStatus() async {
  final isRunning = await FlutterForegroundTask.isRunningService;

  debugPrint('FG Service status → $isRunning');
}
