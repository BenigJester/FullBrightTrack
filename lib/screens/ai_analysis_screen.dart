import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AiAnalysisScreen extends StatefulWidget {
  const AiAnalysisScreen({super.key});

  @override
  State<AiAnalysisScreen> createState() => _AiAnalysisScreenState();
}

class _AiAnalysisScreenState extends State<AiAnalysisScreen> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _statusStream() {
    if (Firebase.apps.isEmpty) return null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('admin_monitoring')
        .doc(user.uid)
        .snapshots();
  }

  Future<void> _refresh() async {
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    final stream = _statusStream();

    return SafeArea(
      child: RefreshIndicator(
        color: Colors.deepOrange,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                final status = _AiMoodStatus.fromDoc(snapshot.data);
                return _AiStatusHero(status: status);
              },
            ),
            const SizedBox(height: 16),
            _DataUseCard(),
            const SizedBox(height: 16),
            const _GuidelinesCard(),
            const SizedBox(height: 16),
            const _SupportContactCard(),
          ],
        ),
      ),
    );
  }
}

class _GuidelinesCard extends StatelessWidget {
  const _GuidelinesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.menu_book_rounded, color: Colors.deepOrange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Guidelines",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GuidelineItem(
            icon: Icons.check_circle_outline_rounded,
            text:
                "Use the analysis as a reflection tool, not as a medical diagnosis.",
          ),
          _GuidelineItem(
            icon: Icons.edit_note_rounded,
            text:
                "Keep mood, journal, task, and steps updated so the AI has enough recent context.",
          ),
          _GuidelineItem(
            icon: Icons.priority_high_rounded,
            text:
                "If the status is High or you feel unsafe, contact a trusted person or support staff immediately.",
          ),
          _GuidelineItem(
            icon: Icons.privacy_tip_outlined,
            text:
                "Raw entries are used only when you consent. You can still use the app without treating the score as final.",
          ),
        ],
      ),
    );
  }
}

class _GuidelineItem extends StatelessWidget {
  const _GuidelineItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.deepOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
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

class _SupportContactCard extends StatelessWidget {
  const _SupportContactCard();

  static const _supportNumber = '+639171234567';

  Future<void> _callSupport(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: _supportNumber);
    final launched = await launchUrl(uri);
    if (launched || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Could not open the phone dialer")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Need support?",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "If your analysis feels concerning or you need help now, contact a trusted support person.",
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _callSupport(context),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.phone_rounded),
            label: const Text("Call support $_supportNumber"),
          ),
        ],
      ),
    );
  }
}

class _AiStatusHero extends StatelessWidget {
  const _AiStatusHero({required this.status});

  final _AiMoodStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
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
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(status.icon, color: color, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "AI Analysis",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
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
                  label: "Stress level",
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

class _DataUseCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.deepOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "This analysis uses consented raw wellness signals such as mood check-ins, step logs, journal entries, task load, and warning labels. It is an aid for reflection, not a diagnosis.",
              style: TextStyle(
                color: Colors.grey.shade800,
                height: 1.38,
                fontWeight: FontWeight.w600,
              ),
            ),
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
            "Your AI analysis will appear after FullBrightTrack has recent mood, steps, journal, or task signals to review.",
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
        return 'Recent signals show a high support need. Consider reaching out to someone trusted or school support staff today.';
      case 'Elevated':
        return 'Recent signals suggest rising pressure. A check-in, lighter workload, or rest plan may help.';
      case 'Moderate':
        return 'Your signals look mixed. Keep monitoring your energy, tasks, and mood so small issues do not build up.';
      default:
        return 'Recent wellness signals look generally steady. Keep logging honestly so this analysis remains useful.';
    }
  }
}
