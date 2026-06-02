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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFFF97316),
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                sliver: SliverList.list(
                  children: [
                    Text(
                      'Wellness AI',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'A simple summary of your recent wellness signals.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: stream,
                      builder: (context, snapshot) {
                        final status = _AiMoodStatus.fromDoc(snapshot.data);
                        return Column(
                          children: [
                            _AiStatusHero(
                              status: status,
                              isLoading:
                                  stream != null &&
                                  snapshot.connectionState ==
                                      ConnectionState.waiting,
                              isOffline: stream == null,
                            ),
                            if (status.rank == 'High') ...[
                              const SizedBox(height: 16),
                              const _SupportContactCard(),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const _DataUseCard(),
                    const SizedBox(height: 16),
                    const _GuidelinesCard(),
                    const SizedBox(height: 12),
                    const _FooterNote(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiStatusHero extends StatelessWidget {
  const _AiStatusHero({
    required this.status,
    required this.isLoading,
    required this.isOffline,
  });

  final _AiMoodStatus status;
  final bool isLoading;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.color;
    final progress = status.confidence <= 0 ? 0.0 : status.score / 100;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.22) ?? color],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(status.icon, color: color, size: 34),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatusPill(
                          text: isOffline
                              ? 'Not connected'
                              : isLoading
                              ? 'Updating'
                              : status.rank,
                          color: color,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          status.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF111827),
                            fontWeight: FontWeight.w900,
                            height: 1.12,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                isOffline
                    ? 'AI analysis is unavailable until Firebase and a signed-in student account are ready.'
                    : status.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF334155),
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              _ScorePanel(status: status, progress: progress, color: color),
              const SizedBox(height: 16),
              if (status.rationale.isNotEmpty) ...[
                Text(
                  'Signals reviewed',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final reason in status.rationale)
                      _ReasonChip(label: reason, color: color),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScorePanel extends StatelessWidget {
  const _ScorePanel({
    required this.status,
    required this.progress,
    required this.color,
  });

  final _AiMoodStatus status;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasScore = status.confidence > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasScore)
            Column(
              children: [
                _StressLevelBlock(status: status, color: color),
                const SizedBox(height: 10),
                _ConfidenceBlock(confidence: status.confidence),
              ],
            )
          else
            _StressLevelBlock(status: status, color: color),
          if (hasScore) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 10,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 8),
            const _StressScale(),
          ],
          const SizedBox(height: 8),
          Text(
            hasScore
                ? 'This score is based on recent logged signals and may change as new data is added.'
                : 'Add recent mood, journal, tasks, or steps data to generate a more useful result.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StressLevelBlock extends StatelessWidget {
  const _StressLevelBlock({required this.status, required this.color});

  final _AiMoodStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasScore = status.confidence > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.monitor_heart_rounded, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stress level',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status.rank,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (hasScore) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${status.score.toStringAsFixed(0)} / 100',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfidenceBlock extends StatelessWidget {
  const _ConfidenceBlock({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF4F46E5);
    final theme = Theme.of(context);
    final percent = (confidence * 100).clamp(0, 100).toStringAsFixed(0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confidence',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'AI certainty',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '$percent%',
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StressScale extends StatelessWidget {
  const _StressScale();

  @override
  Widget build(BuildContext context) {
    const labels = ['Low', 'Moderate', 'Elevated', 'High'];
    const colors = [
      Color(0xFF16A34A),
      Color(0xFFD97706),
      Color(0xFFF97316),
      Color(0xFFDC2626),
    ];

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: color, size: 7),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataUseCard extends StatelessWidget {
  const _DataUseCard();

  @override
  Widget build(BuildContext context) {
    return const _InfoCard(
      icon: Icons.auto_awesome_rounded,
      iconColor: Color(0xFFF97316),
      title: 'How your data is used',
      body:
          'This analysis uses consented wellness signals such as mood check-ins, step logs, journal entries, task load, and warning labels. It is designed for reflection and support, not medical diagnosis.',
      backgroundColor: Color(0xFFFFF7ED),
      borderColor: Color(0xFFFED7AA),
    );
  }
}

class _GuidelinesCard extends StatelessWidget {
  const _GuidelinesCard();

  @override
  Widget build(BuildContext context) {
    return _BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _SectionHeader(
            icon: Icons.menu_book_rounded,
            title: 'Guidelines',
            subtitle:
                'Use the result as a helpful check-in, not a final judgment.',
          ),
          SizedBox(height: 14),
          _GuidelineItem(
            icon: Icons.fact_check_rounded,
            text:
                'Review the analysis together with how you actually feel today.',
          ),
          _GuidelineItem(
            icon: Icons.edit_note_rounded,
            text:
                'Keep mood, journal, task, and steps data updated for better context.',
          ),
          _GuidelineItem(
            icon: Icons.volunteer_activism_rounded,
            text:
                'If the status is High or you feel unsafe, contact a trusted person or school support staff immediately.',
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFF97316), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF334155),
                height: 1.42,
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
      const SnackBar(content: Text('Could not open the phone dialer')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.support_agent_rounded,
            title: 'Need support?',
            subtitle: 'Help is available when the analysis feels concerning.',
          ),
          const SizedBox(height: 14),
          Text(
            'Talk to a trusted support person, adviser, guardian, or school staff member. In urgent situations, seek immediate local emergency help.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475569),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _callSupport(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.phone_rounded),
            label: const Text('Call support $_supportNumber'),
          ),
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Pull down to refresh. Your result updates when new wellness data is available.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: const Color(0xFF94A3B8),
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.backgroundColor,
    required this.borderColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.42,
                    fontWeight: FontWeight.w600,
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

class _BaseCard extends StatelessWidget {
  const _BaseCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF97316).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: const Color(0xFFF97316), size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiMoodStatus {
  const _AiMoodStatus({
    required this.title,
    required this.rank,
    required this.score,
    required this.confidence,
    required this.rationale,
    required this.message,
  });

  factory _AiMoodStatus.fromDoc(DocumentSnapshot<Map<String, dynamic>>? doc) {
    final data = doc?.data();
    if (data == null) {
      return const _AiMoodStatus(
        title: 'Collecting signals',
        rank: 'Pending',
        score: 0,
        confidence: 0,
        rationale: ['waiting for raw data'],
        message:
            'Your AI analysis will appear after FullBrightTrack has recent mood, steps, journal, or task signals to review.',
      );
    }

    final rank = (data['stressRank'] as String?) ?? 'Low';
    final confidence = ((data['confidence'] as num?)?.toDouble() ?? 0)
        .clamp(0.0, 1.0)
        .toDouble();
    final resolvedWarningSignature =
        (data['resolvedWarningSignature'] as String?) ?? '';
    final warningSignature = (data['warningSignature'] as String?) ?? '';
    final hasActiveWarning =
        (data['hasDangerWarning'] as bool?) == true ||
        (warningSignature.isNotEmpty &&
            warningSignature != resolvedWarningSignature);
    final supportResolved =
        resolvedWarningSignature.isNotEmpty && !hasActiveWarning;
    final visibleScore = ((data['stressScore'] as num?)?.toDouble() ?? 0)
        .clamp(0.0, 100.0)
        .toDouble();
    final safeRank = confidence <= 0 && !supportResolved ? 'Pending' : rank;
    final title = (data['aiMoodStatus'] as String?) ?? _titleForRank(safeRank);
    final rawRationale =
        (data['rationale'] as List?)
            ?.whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .take(4)
            .toList() ??
        const ['recent wellness signals'];
    final rationale = supportResolved
        ? [
            'therapist support was provided',
            ...rawRationale.where(
              (reason) =>
                  !reason.toLowerCase().contains('critical journal warning'),
            ),
          ].take(4).toList()
        : rawRationale;

    return _AiMoodStatus(
      title: title,
      rank: safeRank,
      score: visibleScore,
      confidence: confidence,
      rationale: rationale,
      message: _messageForRank(safeRank),
    );
  }

  final String title;
  final String rank;
  final double score;
  final double confidence;
  final List<String> rationale;
  final String message;

  Color get color {
    switch (rank) {
      case 'High':
        return const Color(0xFFDC2626);
      case 'Elevated':
        return const Color(0xFFF97316);
      case 'Moderate':
        return const Color(0xFFD97706);
      case 'Pending':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF16A34A);
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
        return Icons.check_circle_rounded;
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
      case 'Pending':
        return 'Collecting signals';
      default:
        return 'Stable and balanced';
    }
  }

  static String _messageForRank(String rank) {
    switch (rank) {
      case 'High':
        return 'Recent signals show a high support need. Reach out to someone trusted or school support staff today.';
      case 'Elevated':
        return 'Recent signals suggest rising pressure. A check-in, lighter workload, or rest plan may help.';
      case 'Moderate':
        return 'Your signals look mixed. Keep monitoring your energy, tasks, and mood so small issues do not build up.';
      case 'Pending':
        return 'Your AI analysis is still waiting for enough recent signals to estimate a stress score.';
      default:
        return 'Recent wellness signals look generally steady. Keep logging honestly so this analysis remains useful.';
    }
  }
}
