import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_data.dart';

class StepsTab extends StatelessWidget {
  const StepsTab({super.key});

  final double iconRadius = 12;

  Offset polarToCartesian(double radius, double angle, Offset center) {
    return Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            children: [
              const SizedBox(height: 20),

              Row(
                children: [
                  _buildProgressCircle(data),

                  const SizedBox(width: 20),

                  Expanded(child: _buildStatsPanel(data)),
                ],
              ),

              const SizedBox(height: 20),

              _buildStreakCard(data),

              const SizedBox(height: 12),

              _buildTrendCard(data),

              const SizedBox(height: 12),

              _buildInsightsList(data),
            ],
          ),
        ),
      ),
    );
  }

  // ================= PROGRESS =================

  Widget _buildProgressCircle(AppData data) {
    final double ringThickness = iconRadius * 2;

    double stepProgress = (data.stepsToday / data.stepGoal).clamp(0, 1.0);

    double calorieProgress = (data.calories / 300).clamp(0, 1.0);

    double outerSize = 180;
    double innerSize = outerSize - (ringThickness * 3);

    final center = Offset(outerSize / 2, outerSize / 2);

    const double gapAngleRad = -pi / 2;

    final outerRadius = (outerSize / 2) - (ringThickness / 2);

    final innerRadius = (innerSize / 2) - (ringThickness / 2);

    final outerIconPos = polarToCartesian(outerRadius, gapAngleRad, center);

    final innerIconPos = polarToCartesian(innerRadius, gapAngleRad, center);

    const double gapPx = 60;

    return SizedBox(
      height: outerSize,
      width: outerSize,

      child: Stack(
        children: [
          CustomPaint(
            size: Size(outerSize, outerSize),

            painter: RingPainter(
              progress: stepProgress,
              strokeWidth: ringThickness,
              backgroundColor: Colors.orange.withValues(alpha: 0.15),
              progressColor: Colors.deepOrange,
              gapWidthPx: gapPx,
            ),
          ),

          Positioned.fill(
            child: Center(
              child: SizedBox(
                height: innerSize,
                width: innerSize,

                child: CustomPaint(
                  painter: RingPainter(
                    progress: calorieProgress,
                    strokeWidth: ringThickness,
                    backgroundColor: Colors.orange.shade100,
                    progressColor: Colors.orange,
                    gapWidthPx: gapPx,
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: outerIconPos.dx - iconRadius,
            top: outerIconPos.dy - iconRadius,

            child: Icon(
              Icons.directions_walk,
              size: iconRadius * 2,
              color: Colors.deepOrange,
            ),
          ),

          Positioned(
            left: innerIconPos.dx - iconRadius,
            top: innerIconPos.dy - iconRadius,

            child: Icon(
              Icons.local_fire_department,
              size: iconRadius * 2,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  // ================= STATS =================

  Widget _buildStatsPanel(AppData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statItem(Colors.deepOrange, "Steps"),
        Text("${data.stepsToday} / ${data.stepGoal}"),

        const SizedBox(height: 16),

        _statItem(Colors.orange, "Calories"),
        Text("${data.calories.toStringAsFixed(0)} / 300"),

        const SizedBox(height: 16),

        _statItem(Colors.amber, "Distance"),
        Text("${data.distance.toStringAsFixed(2)} KM"),

        const SizedBox(height: 16),

        Text(
          data.debugText,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _statItem(Color color, String title) {
    return Row(
      children: [
        Text("●", style: TextStyle(fontSize: 16, color: color)),

        const SizedBox(width: 6),

        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ================= STREAK =================

  Widget _buildStreakCard(AppData data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8A65), Color(0xFFFF7043)],
        ),

        borderRadius: BorderRadius.circular(22),
      ),

      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,

        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const Text(
                "Current Streak",
                style: TextStyle(color: Colors.white70),
              ),

              const SizedBox(height: 6),

              Text(
                "${data.currentStreak} days 🔥",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),

          Text(
            "${data.longestStreak} Best",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ================= TREND =================

  Widget _buildTrendCard(AppData data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade100, Colors.deepOrange.shade100],
        ),

        borderRadius: BorderRadius.circular(22),

        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),

            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),

            child: Icon(
              data.trend == "up"
                  ? Icons.trending_up
                  : data.trend == "down"
                  ? Icons.trending_down
                  : Icons.trending_flat,
              color: Colors.deepOrange,
              size: 30,
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  "Weekly Trend",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  data.trendLabel,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= INSIGHTS =================

  Widget _buildInsightsList(AppData data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),

        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Text(
            "Health Insights",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 14),

          ...data.insights.map((insight) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
              ),

              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  const Text("🔥", style: TextStyle(fontSize: 18)),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      insight,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ================= RING PAINTER =================

class RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color backgroundColor;
  final Color progressColor;
  final double gapWidthPx;

  RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.progressColor,
    required this.gapWidthPx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    final gapAngle = gapWidthPx / radius;
    final startAngle = -pi / 2 + gapAngle / 2;
    final sweepAngle = 2 * pi - gapAngle;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);
    canvas.drawArc(rect, startAngle, sweepAngle * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// ==================== Streak Engine ========================
class HealthInsights {
  final int currentStreak;
  final int longestStreak;
  final String trend;
  final double trendPercent;
  final String trendLabel;
  final List<String> insights;

  HealthInsights({
    required this.currentStreak,
    required this.longestStreak,
    required this.trend,
    required this.trendPercent,
    required this.trendLabel,
    required this.insights,
  });
}
