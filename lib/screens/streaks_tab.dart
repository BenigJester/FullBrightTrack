import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_data.dart';
import '../services/steps_service.dart';

class StreakTab extends StatelessWidget {
  const StreakTab({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();

    final streak = {
      "current": data.currentStreak,
      "longest": data.longestStreak,
    };

    final moodStreak = {
      "current": data.moodCurrentStreak,
      "longest": data.moodLongestStreak,
    };

    final trend = {
      "trend": data.trendType,
      "label": data.trendLabelStreak,
      "percent": data.streakTrendPercent,
    };

    return RefreshIndicator(
      color: Colors.deepOrange,
      onRefresh: StepsService.instance.refreshNow,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AspectRatio(aspectRatio: 1, child: _heroCard(streak)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _moodStreakCard(moodStreak),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _consistencyRow(data),
            const SizedBox(height: 16),

            _trendCard(trend),
            const SizedBox(height: 16),

            _calendarHeatmap(data),
          ],
        ),
      ),
    );
  }

  // ================= HERO =================

  Widget _heroCard(Map<String, int> streak) {
    const color = Color(0xFFEA580C);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 170;
        final padding = compact ? 11.0 : 16.0;
        final topGap = compact ? 8.0 : 14.0;
        final labelGap = compact ? 4.0 : 6.0;
        final badgeGap = compact ? 6.0 : 10.0;

        return Container(
          padding: EdgeInsets.all(padding),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),

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
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(compact ? 7 : 8),

                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),

                    child: Icon(
                      Icons.local_fire_department_rounded,
                      color: color,
                      size: compact ? 18 : 20,
                    ),
                  ),

                  const Spacer(),

                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 7 : 9,
                      vertical: compact ? 4 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      "Steps",
                      style: TextStyle(
                        color: color,
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: topGap),

              Text(
                "${streak["current"]}",
                style: TextStyle(
                  color: const Color(0xFF111827),
                  fontSize: compact ? 28 : 32,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),

              SizedBox(height: labelGap),

              Text(
                "Step streak",
                style: TextStyle(
                  color: const Color(0xFF64748B),
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(),

              SizedBox(height: badgeGap),

              _miniBestBadge(
                label: "Best",
                value: "${streak["longest"] ?? 0} days",
                color: color,
                compact: compact,
              ),
            ],
          ),
        );
      },
    );
  }

  // ================= MOOD =================

  Widget _moodStreakCard(Map<String, int> moodStreak) {
    final currentMoodStreak = moodStreak["current"] ?? 0;

    String status;

    if (currentMoodStreak == 0) {
      status = "\u{1F642} Start";
    } else if (currentMoodStreak < 3) {
      status = "\u{1F331} Growing";
    } else if (currentMoodStreak < 7) {
      status = "\u{1F49B} Positive";
    } else {
      status = "\u{1F33F} Balanced";
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 170;
        final padding = compact ? 11.0 : 16.0;
        final topGap = compact ? 8.0 : 14.0;
        final labelGap = compact ? 4.0 : 6.0;
        final badgeGap = compact ? 6.0 : 10.0;

        return Container(
          padding: EdgeInsets.all(padding),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),

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
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(compact ? 7 : 8),

                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),

                    child: Icon(
                      Icons.mood_rounded,
                      color: const Color(0xFF4F46E5),
                      size: compact ? 18 : 20,
                    ),
                  ),

                  const Spacer(),

                  Flexible(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 7 : 9,
                        vertical: compact ? 4 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF4F46E5),
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: topGap),

              Text(
                "${moodStreak["current"]}",
                style: TextStyle(
                  color: const Color(0xFF111827),
                  fontSize: compact ? 28 : 32,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),

              SizedBox(height: labelGap),

              Text(
                "Mood Streak",
                style: TextStyle(
                  color: const Color(0xFF64748B),
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(),

              SizedBox(height: badgeGap),

              _miniBestBadge(
                label: "Best",
                value: "${moodStreak["longest"] ?? 0} days",
                color: const Color(0xFF4F46E5),
                compact: compact,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniBestBadge({
    required String label,
    required String value,
    required Color color,
    bool compact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: const Color(0xFF111827),
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ================= CONSISTENCY =================

  Widget _consistencyRow(AppData data) {
    final consistency = data.consistencyPercent;

    Color consistencyColor;

    String consistencyLabel;

    IconData consistencyIcon;

    if (consistency >= 80) {
      consistencyColor = Colors.deepOrange;
      consistencyLabel = "Excellent";
      consistencyIcon = Icons.local_fire_department_rounded;
    } else if (consistency >= 60) {
      consistencyColor = Colors.orange;
      consistencyLabel = "Great";
      consistencyIcon = Icons.trending_up_rounded;
    } else if (consistency >= 40) {
      consistencyColor = Colors.amber;
      consistencyLabel = "Good";
      consistencyIcon = Icons.bolt_rounded;
    } else {
      consistencyColor = Colors.grey;
      consistencyLabel = "Keep Going";
      consistencyIcon = Icons.favorite_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: consistencyColor.withValues(alpha: 0.15)),

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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),

                decoration: BoxDecoration(
                  color: consistencyColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),

                child: Icon(consistencyIcon, color: consistencyColor, size: 20),
              ),

              const Spacer(),

              Text(
                consistencyLabel,
                style: TextStyle(
                  color: consistencyColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: consistency),
            duration: const Duration(milliseconds: 900),

            builder: (context, value, child) {
              return Text(
                "${value.toStringAsFixed(0)}%",
                style: TextStyle(
                  color: consistencyColor,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              );
            },
          ),

          const SizedBox(height: 6),

          const Text(
            "Consistency",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),

            child: LinearProgressIndicator(
              value: consistency / 100,
              minHeight: 7,

              backgroundColor: Colors.grey.shade200,

              valueColor: AlwaysStoppedAnimation(consistencyColor),
            ),
          ),
        ],
      ),
    );
  }

  // ================= HEATMAP =================

  Widget _calendarHeatmap(AppData data) {
    final now = DateTime.now();

    // ================= CURRENT MONTH =================

    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    final firstDay = DateTime(now.year, now.month, 1);

    // Monday = 1 ... Sunday = 7
    final startWeekday = firstDay.weekday;

    // ================= WEEK LABELS =================

    final weekLabels = ["M", "T", "W", "T", "F", "S", "S"];

    List<Widget> cells = [];

    // ================= EMPTY START SPACES =================

    for (int i = 1; i < startWeekday; i++) {
      cells.add(const SizedBox(width: 38, height: 38));
    }

    // ================= CALENDAR DAYS =================

    for (int day = 1; day <= daysInMonth; day++) {
      final dateKey =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}";

      final steps = data.streakStepsData[dateKey] ?? 0;

      Color color;

      if (steps == 0) {
        color = Colors.grey.shade200;
      } else if (steps < data.stepGoal * 0.5) {
        color = Colors.orange.shade200;
      } else if (steps < data.stepGoal) {
        color = Colors.orange;
      } else {
        color = Colors.deepOrange;
      }

      final isToday = day == now.day;

      cells.add(
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),

          width: 38,
          height: 38,

          alignment: Alignment.center,

          decoration: BoxDecoration(
            color: color,

            borderRadius: BorderRadius.circular(10),

            border: isToday
                ? Border.all(color: Colors.black87, width: 2)
                : null,

            boxShadow: [
              if (steps > 0)
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
            ],
          ),

          child: Text(
            "$day",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: steps == 0 ? Colors.grey.shade700 : Colors.white,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // ================= HEADER =================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [
              const Text(
                "Monthly Activity",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              Text(
                "${now.month}/${now.year}",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ================= WEEK LABELS =================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekLabels.map((label) {
              return SizedBox(
                width: 38,
                height: 20,

                child: Center(
                  child: Text(
                    label,

                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // ================= GRID =================
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemBuilder: (_, index) => cells[index],
          ),

          const SizedBox(height: 18),

          // ================= LEGEND =================
          Row(
            children: [
              _legendBox(Colors.grey.shade200, "No Data"),
              const SizedBox(width: 10),

              _legendBox(Colors.orange.shade200, "Low"),
              const SizedBox(width: 10),

              _legendBox(Colors.orange, "Good"),
              const SizedBox(width: 10),

              _legendBox(Colors.deepOrange, "Goal"),
            ],
          ),
        ],
      ),
    );
  }

  // ================= LEGEND =================

  Widget _legendBox(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,

          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),

        const SizedBox(width: 4),

        Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }

  // ================= TREND =================

  Widget _trendCard(Map<String, dynamic> t) {
    final String label = t["label"];
    final double percent = (t["percent"] ?? 0).toDouble();

    late String text;
    late IconData icon;
    late Color bgColor;
    late Color iconColor;
    late Color textColor;

    // ================= STATES =================

    if (label == "No activity") {
      text = "No activity recorded this week";
      icon = Icons.nightlight_round;

      bgColor = const Color(0xFFF3F4F6);
      iconColor = Colors.grey;
      textColor = Colors.black87;
    } else if (label == "Started") {
      text = "You started being active \u{1F389}";
      icon = Icons.local_fire_department_rounded;

      bgColor = const Color(0xFFFFF3E0);
      iconColor = Colors.deepOrange;
      textColor = Colors.deepOrange.shade700;
    } else if (label == "Stopped") {
      text = "Activity stopped recently \u{26A0}\u{FE0F}";
      icon = Icons.trending_down_rounded;

      bgColor = const Color(0xFFFFEBEE);
      iconColor = Colors.redAccent;
      textColor = Colors.red.shade700;
    } else if (t["trend"] == "up") {
      text =
          "You're improving by "
          "${percent.toStringAsFixed(1)}% this week \u{1F680}";

      icon = Icons.trending_up_rounded;

      bgColor = const Color(0xFFE8F5E9);
      iconColor = Colors.green;
      textColor = Colors.green.shade700;
    } else if (t["trend"] == "down") {
      text =
          "Activity decreased by "
          "${percent.abs().toStringAsFixed(1)}%";

      icon = Icons.trending_down_rounded;

      bgColor = const Color(0xFFFFF3E0);
      iconColor = Colors.orange;
      textColor = Colors.orange.shade800;
    } else {
      text = "Your activity stayed stable this week";
      icon = Icons.balance_rounded;

      bgColor = const Color(0xFFE3F2FD);
      iconColor = Colors.blue;
      textColor = Colors.blue.shade700;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: iconColor.withValues(alpha: 0.14)),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),

      child: Row(
        children: [
          // ================= ICON =================
          Container(
            width: 52,
            height: 52,

            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),

            child: Icon(icon, color: iconColor, size: 28),
          ),

          const SizedBox(width: 14),

          // ================= TEXT =================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  "Weekly Trend",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
