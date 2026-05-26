import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/local_stress_model_service.dart';

class AdminMonitoringScreen extends StatefulWidget {
  const AdminMonitoringScreen({super.key});

  @override
  State<AdminMonitoringScreen> createState() => _AdminMonitoringScreenState();
}

class _AdminMonitoringScreenState extends State<AdminMonitoringScreen> {
  late Future<_AdminDashboardData> _dashboardFuture;
  _AdminRange _range = _AdminRange.week;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<void> _refresh() async {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });

    await _dashboardFuture;
  }

  Future<_AdminDashboardData> _loadDashboard() async {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 29));
    final dateKeys = List.generate(30, (index) {
      return _dateKey(start.add(Duration(days: index)));
    });

    final users = await FirebaseFirestore.instance
        .collection('admin_monitoring')
        .orderBy('stressScore', descending: true)
        .limit(50)
        .get();

    final summaries = <_StudentWellnessSummary>[];

    for (final doc in users.docs) {
      final summary = _summaryFromMonitoringDoc(doc, dateKeys);

      summaries.add(summary);
    }

    return _AdminDashboardData(
      students: summaries,
      generatedAt: now,
      dateKeys: dateKeys,
    );
  }

  _StudentWellnessSummary _summaryFromMonitoringDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    List<String> dateKeys,
  ) {
    final data = doc.data();
    final modelResult = StressModelResult(
      score: (data['stressScore'] as num?)?.toDouble() ?? 0,
      rank: (data['stressRank'] as String?) ?? 'Low',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      modelVersion: (data['modelVersion'] as String?) ?? 'unknown',
      rationale:
          (data['rationale'] as List?)?.whereType<String>().take(3).toList() ??
          const ['No rationale recorded'],
    );
    final dailyStress = {for (final day in dateKeys) day: modelResult.score};

    return _StudentWellnessSummary(
      uid: doc.id,
      name: _displayName(data),
      email: (data['email'] as String?)?.trim() ?? '',
      photoUrl: data['photoUrl'] as String?,
      stressScore: modelResult.score,
      stressRank: modelResult.rank,
      averageSteps: ((data['avgDailySteps'] as num?)?.toDouble() ?? 0).round(),
      moodEntries: (((data['moodLogCoverage'] as num?)?.toDouble() ?? 0) * 30)
          .round(),
      journalEntries: (data['journalEntryCount'] as num?)?.toInt() ?? 0,
      averageMood: (data['avgMoodIndex'] as num?)?.toDouble() ?? 0,
      averageIntensity: (data['avgMoodIntensity'] as num?)?.toDouble() ?? 0,
      activeTasks: (data['activeTaskCount'] as num?)?.toInt() ?? 0,
      completedTasks: (data['completedTaskCount'] as num?)?.toInt() ?? 0,
      overdueTasks: (data['overdueTaskCount'] as num?)?.toInt() ?? 0,
      dailyStress: dailyStress,
      warningSnippets:
          (data['warningSnippets'] as List?)?.whereType<String>().toList() ??
          const [],
      mlFeatures: _PersonalMlFeatures(
        avgMoodIndex: (data['avgMoodIndex'] as num?)?.toDouble() ?? 0,
        avgMoodIntensity: (data['avgMoodIntensity'] as num?)?.toDouble() ?? 0,
        avgDailySteps: (data['avgDailySteps'] as num?)?.toDouble() ?? 0,
        moodLogCoverage: (data['moodLogCoverage'] as num?)?.toDouble() ?? 0,
        journalEntryCount: (data['journalEntryCount'] as num?)?.toInt() ?? 0,
        activeTaskCount: (data['activeTaskCount'] as num?)?.toInt() ?? 0,
        completedTaskCount: (data['completedTaskCount'] as num?)?.toInt() ?? 0,
        overdueTaskCount: (data['overdueTaskCount'] as num?)?.toInt() ?? 0,
        journalWarningWeight:
            (data['journalWarningWeight'] as num?)?.toDouble() ?? 0,
        journalWarningSeverity:
            (data['journalWarningSeverity'] as String?) ?? 'none',
        source: (data['source'] as String?) ?? 'admin_monitoring',
        modelResult: modelResult,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          "Admin Monitoring",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: "Stress rank guide",
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => _showStressGuide(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<_AdminDashboardData>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(onRetry: _refresh);
          }

          final data = snapshot.data ?? _AdminDashboardData.empty();

          return RefreshIndicator(
            color: Colors.deepOrange,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                _SummaryHeader(data: data),
                const SizedBox(height: 14),
                _RangeSelector(
                  selected: _range,
                  onChanged: (range) => setState(() => _range = range),
                ),
                const SizedBox(height: 14),
                _StressChart(students: data.students, range: _range),
                const SizedBox(height: 16),
                for (final student in data.students)
                  _StudentCard(student: student, range: _range),
                if (data.students.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: Text("No student data found")),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showStressGuide(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Stress rank guide",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              _GuideRow(label: "70+", value: "High", color: Colors.red),
              _GuideRow(
                label: "45-69",
                value: "Elevated",
                color: Colors.deepOrange,
              ),
              _GuideRow(
                label: "25-44",
                value: "Moderate",
                color: Colors.amber.shade700,
              ),
              const _GuideRow(label: "<25", value: "Low", color: Colors.green),
              const SizedBox(height: 12),
              Text(
                "Current score is produced by a local, minimized AI-style model. It does not send journal text or personal data to a cloud API and should be reviewed by a human.",
                style: TextStyle(color: Colors.grey.shade700, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.data});

  final _AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final highCount = data.students
        .where((student) => student.stressScore >= 70)
        .length;
    final averageStress = data.students.isEmpty
        ? 0.0
        : data.students
                  .map((student) => student.stressScore)
                  .reduce((a, b) => a + b) /
              data.students.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Student wellness overview",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: "Users",
                  value: "${data.students.length}",
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(
                  label: "Avg stress",
                  value: averageStress.toStringAsFixed(0),
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(
                  label: "High",
                  value: "$highCount",
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onChanged});

  final _AdminRange selected;
  final ValueChanged<_AdminRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_AdminRange>(
      selected: {selected},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.deepOrange
              : Colors.white;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.black87;
        }),
      ),
      segments: const [
        ButtonSegment(value: _AdminRange.day, label: Text("Day")),
        ButtonSegment(value: _AdminRange.week, label: Text("Week")),
        ButtonSegment(value: _AdminRange.month, label: Text("Month")),
      ],
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _StressChart extends StatelessWidget {
  const _StressChart({required this.students, required this.range});

  final List<_StudentWellnessSummary> students;
  final _AdminRange range;

  @override
  Widget build(BuildContext context) {
    final points = _aggregateStress(students, range);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            "Stress signal chart",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: (point.value / 100).clamp(
                                  0.05,
                                  1,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _stressColor(point.value),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            point.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
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

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.range});

  final _StudentWellnessSummary student;
  final _AdminRange range;

  @override
  Widget build(BuildContext context) {
    final points = _studentPoints(student, range);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: student.photoUrl != null
                    ? NetworkImage(student.photoUrl!)
                    : null,
                child: student.photoUrl == null
                    ? Text(student.name.characters.first.toUpperCase())
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      student.email.isEmpty ? student.uid : student.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              _RankBadge(rank: student.stressRank, score: student.stressScore),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: "Steps",
                  value: "${student.averageSteps}",
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  label: "Mood logs",
                  value: "${student.moodEntries}",
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  label: "Journals",
                  value: "${student.journalEntries}",
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: "Active",
                  value: "${student.activeTasks}",
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  label: "Done",
                  value: "${student.completedTasks}",
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  label: "Overdue",
                  value: "${student.overdueTasks}",
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (student.warningSnippets.isNotEmpty) ...[
            _WarningSnippetPanel(snippets: student.warningSnippets),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final point in points)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: max(8, point.value / 100 * 54),
                      decoration: BoxDecoration(
                        color: _stressColor(point.value),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _PersonalMlPanel(features: student.mlFeatures),
        ],
      ),
    );
  }
}

class _WarningSnippetPanel extends StatelessWidget {
  const _WarningSnippetPanel({required this.snippets});

  final List<String> snippets;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Journal warning signal",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final snippet in snippets.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                snippet,
                style: TextStyle(color: Colors.red.shade800, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonalMlPanel extends StatelessWidget {
  const _PersonalMlPanel({required this.features});

  final _PersonalMlFeatures features;

  @override
  Widget build(BuildContext context) {
    final readySignals = features.readySignalCount;
    final ready = readySignals >= 3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.psychology_alt_rounded : Icons.pending_outlined,
                color: ready ? Colors.deepOrange : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready ? "AI stress estimate" : "Needs more signals",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                "$readySignals/4",
                style: TextStyle(
                  color: ready ? Colors.deepOrange : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SignalChip(
                label: "Mood",
                ready: features.hasMoodSignal,
                value: features.avgMoodIndex.toStringAsFixed(1),
              ),
              _SignalChip(
                label: "Steps",
                ready: features.hasStepSignal,
                value: features.avgDailySteps.toStringAsFixed(0),
              ),
              _SignalChip(
                label: "Journal",
                ready: features.hasJournalSignal,
                value: "${features.journalEntryCount}",
              ),
              _SignalChip(
                label: "Warning",
                ready: features.journalWarningWeight > 0,
                value: features.journalWarningLabel,
              ),
              _SignalChip(
                label: "Tasks",
                ready: features.hasTaskSignal,
                value: "${features.totalTaskCount}",
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: "AI rank",
                  value: features.modelResult.rank,
                  color: _stressColor(features.modelResult.score),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  label: "Confidence",
                  value:
                      "${(features.modelResult.confidence * 100).toStringAsFixed(0)}%",
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Rationale: ${features.modelResult.rationale.join(', ')}. Human review required before any action.",
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Based on minimized mood, activity, journal warning weight, and task signals. Model: ${features.modelResult.modelVersion}.",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.label,
    required this.ready,
    required this.value,
  });

  final String label;
  final bool ready;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.green : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: color,
            size: 15,
          ),
          const SizedBox(width: 5),
          Text(
            "$label $value",
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 66,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
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
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.score});

  final String rank;
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = _stressColor(score);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            rank,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          Text(
            score.toStringAsFixed(0),
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: Colors.deepOrange,
              size: 42,
            ),
            const SizedBox(height: 12),
            const Text(
              "Admin data could not be loaded",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              "Check that this account has admin access and Firestore rules allow reading student wellness data.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminDashboardData {
  const _AdminDashboardData({
    required this.students,
    required this.generatedAt,
    required this.dateKeys,
  });

  factory _AdminDashboardData.empty() {
    return _AdminDashboardData(
      students: const [],
      generatedAt: DateTime.now(),
      dateKeys: const [],
    );
  }

  final List<_StudentWellnessSummary> students;
  final DateTime generatedAt;
  final List<String> dateKeys;
}

class _StudentWellnessSummary {
  const _StudentWellnessSummary({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.stressScore,
    required this.stressRank,
    required this.averageSteps,
    required this.moodEntries,
    required this.journalEntries,
    required this.averageMood,
    required this.averageIntensity,
    required this.activeTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.dailyStress,
    required this.warningSnippets,
    required this.mlFeatures,
  });

  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final double stressScore;
  final String stressRank;
  final int averageSteps;
  final int moodEntries;
  final int journalEntries;
  final double averageMood;
  final double averageIntensity;
  final int activeTasks;
  final int completedTasks;
  final int overdueTasks;
  final Map<String, double> dailyStress;
  final List<String> warningSnippets;
  final _PersonalMlFeatures mlFeatures;
}

class _PersonalMlFeatures {
  const _PersonalMlFeatures({
    required this.avgMoodIndex,
    required this.avgMoodIntensity,
    required this.avgDailySteps,
    required this.moodLogCoverage,
    required this.journalEntryCount,
    required this.activeTaskCount,
    required this.completedTaskCount,
    required this.overdueTaskCount,
    required this.journalWarningWeight,
    required this.journalWarningSeverity,
    required this.source,
    required this.modelResult,
  });

  final double avgMoodIndex;
  final double avgMoodIntensity;
  final double avgDailySteps;
  final double moodLogCoverage;
  final int journalEntryCount;
  final int activeTaskCount;
  final int completedTaskCount;
  final int overdueTaskCount;
  final double journalWarningWeight;
  final String journalWarningSeverity;
  final String source;
  final StressModelResult modelResult;

  bool get hasMoodSignal => moodLogCoverage > 0;
  bool get hasStepSignal => avgDailySteps > 0;
  bool get hasJournalSignal => journalEntryCount > 0;
  bool get hasTaskSignal => totalTaskCount > 0;

  int get totalTaskCount =>
      activeTaskCount + completedTaskCount + overdueTaskCount;

  String get journalWarningLabel {
    if (journalWarningWeight <= 0) return 'None';
    if (journalWarningSeverity == 'critical') return 'Critical';
    if (journalWarningSeverity == 'elevated') return 'Elevated';
    return 'Stress';
  }

  int get readySignalCount {
    return [
      hasMoodSignal,
      hasStepSignal,
      hasJournalSignal,
      hasTaskSignal,
      journalWarningWeight > 0,
    ].where((ready) => ready).length;
  }
}

class _ChartPoint {
  const _ChartPoint({required this.label, required this.value});

  final String label;
  final double value;
}

enum _AdminRange { day, week, month }

List<_ChartPoint> _aggregateStress(
  List<_StudentWellnessSummary> students,
  _AdminRange range,
) {
  if (students.isEmpty) return const [];

  final keys = students.first.dailyStress.keys.toList();
  final scopedKeys = _keysForRange(keys, range);

  return scopedKeys.map((key) {
    final values = students.map((student) => student.dailyStress[key] ?? 0);
    final average = values.reduce((a, b) => a + b) / students.length;

    return _ChartPoint(label: _shortLabel(key, range), value: average);
  }).toList();
}

List<_ChartPoint> _studentPoints(
  _StudentWellnessSummary student,
  _AdminRange range,
) {
  final keys = _keysForRange(student.dailyStress.keys.toList(), range);

  return keys
      .map(
        (key) => _ChartPoint(
          label: _shortLabel(key, range),
          value: student.dailyStress[key] ?? 0,
        ),
      )
      .toList();
}

List<String> _keysForRange(List<String> keys, _AdminRange range) {
  if (keys.isEmpty) return const [];

  switch (range) {
    case _AdminRange.day:
      return keys.sublist(max(0, keys.length - 1));
    case _AdminRange.week:
      return keys.sublist(max(0, keys.length - 7));
    case _AdminRange.month:
      return keys;
  }
}

Color _stressColor(double score) {
  if (score >= 70) return Colors.red;
  if (score >= 45) return Colors.deepOrange;
  if (score >= 25) return Colors.amber.shade700;
  return Colors.green;
}

String _displayName(Map<String, dynamic> data) {
  final name = (data['name'] as String?)?.trim();
  if (name != null && name.isNotEmpty) return name;

  final email = (data['email'] as String?)?.trim();
  if (email != null && email.isNotEmpty) return email.split('@').first;

  return 'Student';
}

String _shortLabel(String key, _AdminRange range) {
  final parts = key.split('-');
  if (parts.length != 3) return key;

  if (range == _AdminRange.month) {
    return parts[2];
  }

  return "${parts[1]}/${parts[2]}";
}

String _dateKey(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}
