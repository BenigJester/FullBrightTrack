import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_data.dart';
import '../services/hometab_service.dart';
import '../services/journal_service.dart';
import '../services/moodscreen_service.dart';
import '../services/steps_service.dart';
import '../widgets/ai_updated_status.dart';
import 'mood_popup_card.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const _supportNumber = '+639171234567';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _aiSupportSubscription;
  bool _supportDialogVisible = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await showDailyMotivation(context);
      if (!mounted) return;
      await showMoodPopupIfNeeded(context);
      if (!mounted) return;
      _listenForHighStressSupport();
    });
  }

  @override
  void dispose() {
    _aiSupportSubscription?.cancel();
    super.dispose();
  }

  void _listenForHighStressSupport() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _aiSupportSubscription?.cancel();
    _aiSupportSubscription = FirebaseFirestore.instance
        .collection('admin_monitoring')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          if (data == null || !mounted) return;
          final confidence = ((data['confidence'] as num?)?.toDouble() ?? 0);
          final rank = ((data['stressRank'] as String?) ?? '').trim();
          if (rank == 'High' && confidence > 0) {
            _showHighStressSupportDialog();
          }
        });
  }

  Future<void> _showHighStressSupportDialog() async {
    if (_supportDialogVisible || !mounted) return;
    _supportDialogVisible = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: SingleChildScrollView(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                      decoration: const BoxDecoration(
                        color: Color(0xFFDC2626),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.health_and_safety_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text(
                              "Support is available",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
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
                          const Text(
                            "Your latest wellness analysis shows a high support need. You do not have to handle this alone.",
                            style: TextStyle(
                              color: Color(0xFF111827),
                              height: 1.45,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _supportBullet(
                            Icons.phone_rounded,
                            "Contact a trusted person or support staff now.",
                          ),
                          _supportBullet(
                            Icons.groups_rounded,
                            "If this feels urgent, stay near someone safe.",
                          ),
                          _supportBullet(
                            Icons.favorite_rounded,
                            "Open AI Analysis for the support contact button.",
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      child: Column(
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () async {
                              final uri = Uri(
                                scheme: 'tel',
                                path: _supportNumber,
                              );
                              final launched = await launchUrl(uri);
                              if (launched || !dialogContext.mounted) return;
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not open the phone dialer',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.call_rounded),
                            label: const Text(
                              "Call support",
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text("I understand"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    _supportDialogVisible = false;
  }

  Widget _supportBullet(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFDC2626), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF475569),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
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
    final quickRefresh = Future.wait<void>([
      StepsService.instance.refreshVisibleNow(),
      HomeTabService.loadCached(data).then((_) {}),
    ]).timeout(const Duration(milliseconds: 900), onTimeout: () => <void>[]);

    unawaited(
      Future.wait<void>([
        HomeTabService.preload(data),
        StepsService.instance.refreshNow(),
        MoodService.instance.loadTodayMood(),
      ]).catchError((error) {
        debugPrint('Background home refresh failed: $error');
        return <void>[];
      }),
    );
    unawaited(JournalService.initialize(data));
    await quickRefresh;
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
      return "Calm";
    } else if (intensity < 0.5) {
      return "Mild";
    } else if (intensity < 0.75) {
      return "High";
    } else {
      return "Peak";
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

              _buildAiRecommendation(data),
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

  Widget _buildAiRecommendation(AppData data) {
    final user = FirebaseAuth.instance.currentUser;
    final stream = user == null
        ? null
        : FirebaseFirestore.instance
              .collection('admin_monitoring')
              .doc(user.uid)
              .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final monitoring = snapshot.data?.data() ?? const <String, dynamic>{};
        final recommendation = _recommendationFromAiSignals(data, monitoring);
        final statusText = AiUpdatedStatus.fromMonitoring(monitoring);

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
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.tips_and_updates_rounded,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "AI Recommendation",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                recommendation,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              AiUpdatedStatus(statusText: statusText),
            ],
          ),
        );
      },
    );
  }

  String _recommendationFromAiSignals(
    AppData data,
    Map<String, dynamic> monitoring,
  ) {
    final rank = (monitoring['stressRank'] as String?) ?? '';
    final confidence = ((monitoring['confidence'] as num?)?.toDouble() ?? 0);
    final activeTasks = (monitoring['activeTaskCount'] as num?)?.toInt() ?? 0;
    final overdueTasks = (monitoring['overdueTaskCount'] as num?)?.toInt() ?? 0;

    if (confidence <= 0) {
      return "Choose one small action for the next 10 minutes: drink water, stretch, tidy your workspace, or take a short walk. Keep it simple and decide the next step yourself.";
    }

    if (rank == 'High' || overdueTasks > 2) {
      return "Pause big goals for a moment. Pick one safe, practical action: message someone you trust, step away from the screen, breathe slowly, or handle only the most urgent task.";
    }

    if (rank == 'Elevated' || activeTasks > 5) {
      return "Make today lighter by choosing your top two tasks, then add a short movement break between them. Avoid adding new commitments unless they truly matter.";
    }

    if (data.stepsToday < data.stepGoal) {
      final remaining = data.stepGoal - data.stepsToday;
      return "You can close part of the gap with a calm walk or light movement break. You have $remaining steps left, but stop early if your body needs rest.";
    }

    return "Keep the rest of the day balanced. You have already made progress, so protect your energy with rest, hydration, and one manageable task at a time.";
  }
}
