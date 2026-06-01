import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _aiStatusStream() {
    if (Firebase.apps.isEmpty) return null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('admin_monitoring')
        .doc(user.uid)
        .snapshots();
  }

  Future<void> _refresh() async {
    await MoodService.instance.loadTodayMood();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final moodService = MoodService.instance;
    final stream = _aiStatusStream();

    return RefreshIndicator(
      color: Colors.deepOrange,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              final status = _AiMoodStatus.fromDoc(snapshot.data);
              return _AiMoodStatusCard(status: status);
            },
          ),
          const SizedBox(height: 16),
          _RawSignalCard(),
          const SizedBox(height: 16),
          _MoodCheckInCard(data: data, moodService: moodService),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AiMoodStatusCard extends StatelessWidget {
  const _AiMoodStatusCard({required this.status});

  final _AiMoodStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
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
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(status.icon, color: color, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "AI mood status",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            status.message,
            style: TextStyle(
              color: Colors.grey.shade800,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _StatusMetric(
                  label: "Stress rank",
                  value: status.rank,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatusMetric(
                  label: "Confidence",
                  value: "${(status.confidence * 100).toStringAsFixed(0)}%",
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final reason in status.rationale)
                Chip(
                  label: Text(reason),
                  backgroundColor: color.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RawSignalCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.deepOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "This status is based on raw recent wellness signals you allowed FullBrightTrack to process: mood check-ins, step logs, journal entries, task load, and warning signals.",
              style: TextStyle(
                color: Colors.grey.shade800,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodCheckInCard extends StatelessWidget {
  const _MoodCheckInCard({required this.data, required this.moodService});

  final AppData data;
  final MoodService moodService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's raw mood check-in",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            "Adjust this when your mood changes. It helps the AI status stay current.",
            style: TextStyle(color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(moodService.moods.length, (index) {
              final isSelected = data.selectedMood == index;

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => moodService.updateMood(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.deepOrange.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    moodService.moods[index],
                    style: TextStyle(fontSize: isSelected ? 34 : 28),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                "Intensity",
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: Slider(
                  value: data.moodIntensity,
                  activeColor: Colors.deepOrange,
                  inactiveColor: Colors.orange.shade100,
                  onChanged: (value) {
                    moodService.updateIntensity(value);
                  },
                ),
              ),
              Text(
                "${(data.moodIntensity * 100).toStringAsFixed(0)}%",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ],
      ),
    );
  }
}

class _AiMoodStatus {
  const _AiMoodStatus({
    required this.title,
    required this.rank,
    required this.confidence,
    required this.rationale,
    required this.message,
  });

  factory _AiMoodStatus.fromDoc(DocumentSnapshot<Map<String, dynamic>>? doc) {
    final data = doc?.data();
    if (data == null) {
      return const _AiMoodStatus(
        title: "Collecting signals",
        rank: "Pending",
        confidence: 0,
        rationale: ["waiting for raw data"],
        message:
            "Your AI mood status will appear after FullBrightTrack has recent mood, steps, journal, or task signals to review.",
      );
    }

    final rank = (data['stressRank'] as String?) ?? 'Low';
    final title = (data['aiMoodStatus'] as String?) ?? _titleForRank(rank);
    final rationale =
        (data['rationale'] as List?)?.whereType<String>().take(3).toList() ??
        const ["recent wellness signals"];

    return _AiMoodStatus(
      title: title,
      rank: rank,
      confidence: ((data['confidence'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      rationale: rationale,
      message: _messageForRank(rank),
    );
  }

  final String title;
  final String rank;
  final double confidence;
  final List<String> rationale;
  final String message;

  Color get color {
    switch (rank) {
      case 'High':
        return Colors.red;
      case 'Elevated':
        return Colors.deepOrange;
      case 'Moderate':
        return Colors.amber.shade800;
      case 'Pending':
        return Colors.blueGrey;
      default:
        return Colors.green;
    }
  }

  IconData get icon {
    switch (rank) {
      case 'High':
        return Icons.priority_high_rounded;
      case 'Elevated':
        return Icons.trending_up_rounded;
      case 'Moderate':
        return Icons.balance_rounded;
      case 'Pending':
        return Icons.hourglass_empty_rounded;
      default:
        return Icons.verified_rounded;
    }
  }

  static String _titleForRank(String rank) {
    switch (rank) {
      case 'High':
        return 'Needs urgent support';
      case 'Elevated':
        return 'Needs closer check-in';
      case 'Moderate':
        return 'Mixed but manageable';
      default:
        return 'Stable and balanced';
    }
  }

  static String _messageForRank(String rank) {
    switch (rank) {
      case 'High':
        return 'Your recent raw wellness signals show a high support need. Consider reaching out to a trusted person or school support staff today.';
      case 'Elevated':
        return 'Your recent signals suggest rising pressure. A short check-in, lighter workload, or rest plan may help.';
      case 'Moderate':
        return 'Your signals look mixed. Keep monitoring your energy, tasks, and mood so small issues do not build up.';
      default:
        return 'Your recent raw wellness signals look generally steady. Keep logging honestly so this status remains useful.';
    }
  }
}
