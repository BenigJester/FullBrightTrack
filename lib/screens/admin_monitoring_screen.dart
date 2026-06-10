import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/display_name_service.dart';
import '../services/admin_alert_service.dart';
import '../services/local_stress_model_service.dart';

class AdminMonitoringScreen extends StatefulWidget {
  const AdminMonitoringScreen({
    super.key,
    this.initialUserId,
    this.refreshOnOpen = false,
  });

  final String? initialUserId;
  final bool refreshOnOpen;

  @override
  State<AdminMonitoringScreen> createState() => _AdminMonitoringScreenState();
}

class _AdminMonitoringScreenState extends State<AdminMonitoringScreen> {
  static const int _pageSize = 100;

  late Future<_AdminDashboardData> _dashboardFuture;
  final TextEditingController _pageController = TextEditingController(
    text: '1',
  );
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _studentCardKeys = <String, GlobalKey>{};
  _AdminRange _range = _AdminRange.week;
  _StressRankFilter _rankFilter = _StressRankFilter.all;
  _ConfidenceSort _confidenceSort = _ConfidenceSort.descending;
  String _appliedSearch = '';
  int _page = 1;
  bool _scrolledToHighlightedUser = false;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard(forceServer: widget.refreshOnOpen);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _dashboardFuture = _loadDashboard(forceServer: true);
      _setPage(1);
      _scrolledToHighlightedUser = false;
    });

    await _dashboardFuture;
  }

  Future<_AdminDashboardData> _loadDashboard({bool forceServer = false}) async {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 29));
    final dateKeys = List.generate(30, (index) {
      return _dateKey(start.add(Duration(days: index)));
    });

    final users = await FirebaseFirestore.instance
        .collection('admin_monitoring')
        .orderBy('stressScore', descending: true)
        .limit(1000)
        .get(forceServer ? const GetOptions(source: Source.server) : null);

    final summaries = <_StudentWellnessSummary>[];

    for (final doc in users.docs) {
      final summary = _summaryFromMonitoringDoc(doc, dateKeys);

      summaries.add(summary);
    }

    summaries.sort((a, b) => b.stressScore.compareTo(a.stressScore));

    return _AdminDashboardData(
      students: summaries,
      generatedAt: now,
      dateKeys: dateKeys,
    );
  }

  void _setPage(int page) {
    _page = max(1, page);
    _pageController.text = _page.toString();
  }

  void _goToPage(int page, int totalPages) {
    final nextPage = page.clamp(1, totalPages);
    setState(() {
      _setPage(nextPage);
      _scrolledToHighlightedUser = false;
    });
  }

  void _applyPageInput(int totalPages) {
    final requested = int.tryParse(_pageController.text.trim()) ?? _page;
    _goToPage(requested, totalPages);
  }

  void _applySearch() {
    setState(() {
      _appliedSearch = _searchController.text.trim();
      _setPage(1);
      _scrolledToHighlightedUser = false;
    });
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _appliedSearch = '';
      _setPage(1);
      _scrolledToHighlightedUser = false;
    });
  }

  List<_StudentWellnessSummary> _filteredStudents(
    List<_StudentWellnessSummary> students,
  ) {
    final search = _appliedSearch.trim().toLowerCase();
    final filtered = students.where((student) {
      final rankMatches =
          _rankFilter == _StressRankFilter.all ||
          student.normalizedStressRank == _rankFilter.label;
      if (!rankMatches) return false;
      if (search.isEmpty) return true;

      return student.name.toLowerCase().contains(search) ||
          student.email.toLowerCase().contains(search) ||
          student.uid.toLowerCase().contains(search);
    }).toList();

    filtered.sort((a, b) {
      final highlightedUserId = widget.initialUserId;
      if (highlightedUserId != null && highlightedUserId.isNotEmpty) {
        if (a.uid == highlightedUserId && b.uid != highlightedUserId) return -1;
        if (b.uid == highlightedUserId && a.uid != highlightedUserId) return 1;
      }

      final confidenceOrdered = b.mlFeatures.modelResult.confidence.compareTo(
        a.mlFeatures.modelResult.confidence,
      );
      if (confidenceOrdered != 0) return confidenceOrdered;

      final scoreCompare = a.stressScore.compareTo(b.stressScore);
      return _confidenceSort == _ConfidenceSort.ascending
          ? scoreCompare
          : -scoreCompare;
    });

    return filtered;
  }

  _StudentWellnessSummary _summaryFromMonitoringDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    List<String> dateKeys,
  ) {
    final data = doc.data();
    final storedModelResult = StressModelResult(
      score: (data['stressScore'] as num?)?.toDouble() ?? 0,
      rank: (data['stressRank'] as String?) ?? 'Low',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      modelVersion: (data['modelVersion'] as String?) ?? 'unknown',
      rationale:
          (data['rationale'] as List?)?.whereType<String>().take(3).toList() ??
          const ['No rationale recorded'],
    );
    final warningSignature = (data['warningSignature'] as String?) ?? '';
    final resolvedWarningSignature =
        (data['resolvedWarningSignature'] as String?) ?? '';
    final exactWarningResolved =
        warningSignature.isNotEmpty &&
        warningSignature == resolvedWarningSignature;
    final supportResolved =
        resolvedWarningSignature.isNotEmpty &&
        ((data['hasDangerWarning'] as bool?) != true) &&
        (warningSignature.isEmpty ||
            warningSignature == resolvedWarningSignature);
    final supportResolutionStatus =
        (data['supportResolutionStatus'] as String?) ?? '';
    final warningResolved = exactWarningResolved || supportResolved;
    final warningJournals = _warningJournalsFromData(
      data,
      warningResolved: warningResolved,
    );
    final avgMoodIndex = (data['avgMoodIndex'] as num?)?.toDouble() ?? 0;
    final avgMoodIntensity =
        (data['avgMoodIntensity'] as num?)?.toDouble() ?? 0;
    final avgDailySteps = (data['avgDailySteps'] as num?)?.toDouble() ?? 0;
    final moodLogCoverage = (data['moodLogCoverage'] as num?)?.toDouble() ?? 0;
    final journalEntryCount = (data['journalEntryCount'] as num?)?.toInt() ?? 0;
    final activeTaskCount = (data['activeTaskCount'] as num?)?.toInt() ?? 0;
    final completedTaskCount =
        (data['completedTaskCount'] as num?)?.toInt() ?? 0;
    final overdueTaskCount = (data['overdueTaskCount'] as num?)?.toInt() ?? 0;
    final storedWarningWeight =
        (data['journalWarningWeight'] as num?)?.toDouble() ?? 0;
    final journalWarningWeight = warningResolved ? 0.0 : storedWarningWeight;
    final journalWarningSeverity = warningResolved
        ? 'none'
        : (data['journalWarningSeverity'] as String?) ?? 'none';
    final modelResult = warningResolved && storedWarningWeight > 0
        ? _resolvedWarningModelResult(
            storedModelResult: storedModelResult,
            input: StressModelInput(
              avgMoodIndex: avgMoodIndex,
              avgMoodIntensity: avgMoodIntensity,
              avgDailySteps: avgDailySteps,
              moodLogCoverage: moodLogCoverage,
              journalEntryCount: journalEntryCount,
              activeTaskCount: activeTaskCount,
              completedTaskCount: completedTaskCount,
              overdueTaskCount: overdueTaskCount,
            ),
            supportResolved: supportResolved,
            supportResolutionStatus: supportResolutionStatus,
          )
        : storedModelResult;
    final dailyStress = _stressHistory(data, dateKeys);
    dailyStress[_dateKey(DateTime.now())] = modelResult.score;

    return _StudentWellnessSummary(
      uid: doc.id,
      name: _displayName(data),
      email: (data['email'] as String?)?.trim() ?? '',
      contactPhoneNumber: (data['contactPhoneNumber'] as String?)?.trim() ?? '',
      contactRelationship:
          (data['contactRelationship'] as String?)?.trim() ?? '',
      photoUrl: data['photoUrl'] as String?,
      aiUpdatedAt: _timestampFromData(data),
      stressScore: modelResult.score,
      stressRank: modelResult.rank,
      averageSteps: ((data['avgDailySteps'] as num?)?.toDouble() ?? 0).round(),
      moodEntries: (((data['moodLogCoverage'] as num?)?.toDouble() ?? 0) * 30)
          .round(),
      journalEntries: journalEntryCount,
      averageMood: avgMoodIndex,
      averageIntensity: avgMoodIntensity,
      activeTasks: activeTaskCount,
      completedTasks: completedTaskCount,
      overdueTasks: overdueTaskCount,
      dailyStress: dailyStress,
      warningSnippets: warningResolved
          ? const []
          : (data['warningSnippets'] as List?)?.whereType<String>().toList() ??
                const [],
      warningSignature: warningSignature,
      resolvedWarningSignature: resolvedWarningSignature,
      warningJournals: warningJournals,
      warningJournalId: (data['warningJournalId'] as String?) ?? '',
      warningJournalText: warningResolved
          ? ''
          : (data['warningJournalText'] as String?) ?? '',
      warningJournalCreatedAt:
          (data['warningJournalCreatedAt'] as String?) ?? '',
      mlFeatures: _PersonalMlFeatures(
        avgMoodIndex: avgMoodIndex,
        avgMoodIntensity: avgMoodIntensity,
        avgDailySteps: avgDailySteps,
        moodLogCoverage: moodLogCoverage,
        journalEntryCount: journalEntryCount,
        activeTaskCount: activeTaskCount,
        completedTaskCount: completedTaskCount,
        overdueTaskCount: overdueTaskCount,
        journalWarningWeight: journalWarningWeight,
        journalWarningSeverity: journalWarningSeverity,
        source: (data['source'] as String?) ?? 'admin_monitoring',
        modelResult: modelResult,
      ),
    );
  }

  List<_WarningJournalReview> _warningJournalsFromData(
    Map<String, dynamic> data, {
    required bool warningResolved,
  }) {
    if (warningResolved) return const [];

    final rawList = data['warningJournals'];
    if (rawList is List && rawList.isNotEmpty) {
      return rawList
          .whereType<Map>()
          .map((item) {
            final mapped = Map<String, dynamic>.from(item);
            return _WarningJournalReview(
              id: (mapped['id'] as String?) ?? '',
              signature: (mapped['signature'] as String?) ?? '',
              text: (mapped['text'] as String?) ?? '',
              createdAt: (mapped['createdAt'] as String?) ?? '',
              snippets:
                  (mapped['snippets'] as List?)?.whereType<String>().toList() ??
                  const [],
              severity: (mapped['severity'] as String?) ?? 'critical',
            );
          })
          .where((item) => item.signature.isNotEmpty)
          .toList();
    }

    final signature = (data['warningSignature'] as String?) ?? '';
    if (signature.isEmpty) return const [];

    return [
      _WarningJournalReview(
        id: (data['warningJournalId'] as String?) ?? '',
        signature: signature,
        text: (data['warningJournalText'] as String?) ?? '',
        createdAt: (data['warningJournalCreatedAt'] as String?) ?? '',
        snippets:
            (data['warningSnippets'] as List?)?.whereType<String>().toList() ??
            const [],
        severity: (data['journalWarningSeverity'] as String?) ?? 'critical',
      ),
    ];
  }

  Map<String, double> _stressHistory(
    Map<String, dynamic> data,
    List<String> dateKeys,
  ) {
    final history = data['stressHistory'];
    if (history is! Map) return <String, double>{};

    return {
      for (final entry in history.entries)
        if (dateKeys.contains(entry.key) && entry.value is num)
          entry.key.toString(): (entry.value as num).toDouble(),
    };
  }

  StressModelResult _resolvedWarningModelResult({
    required StressModelResult storedModelResult,
    required StressModelInput input,
    required bool supportResolved,
    required String supportResolutionStatus,
  }) {
    final resolvedResult = LocalStressModelService.analyze(input);
    final rationale = <String>[
      if (supportResolved)
        supportResolutionStatus == 'false_positive'
            ? 'false positive'
            : 'Support was provided',
      'warning reviewed by admin',
      ...resolvedResult.rationale.where(
        (reason) => !reason.toLowerCase().contains('journal warning'),
      ),
    ];

    return StressModelResult(
      score: resolvedResult.score,
      rank: resolvedResult.rank,
      confidence: resolvedResult.confidence,
      modelVersion: '${storedModelResult.modelVersion}+resolved-view',
      rationale: rationale.take(3).toList(),
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
          final filteredStudents = _filteredStudents(data.students);
          final totalPages = max(
            1,
            (filteredStudents.length / _pageSize).ceil(),
          );
          if (_page > totalPages) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _goToPage(totalPages, totalPages);
            });
          }
          final safePage = min(_page, totalPages);
          if (!_scrolledToHighlightedUser &&
              (widget.initialUserId ?? '').isNotEmpty) {
            _scrolledToHighlightedUser = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final targetKey = _studentCardKeys[widget.initialUserId];
              final targetContext = targetKey?.currentContext;
              if (targetContext != null) {
                Scrollable.ensureVisible(
                  targetContext,
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  alignment: 0.16,
                );
                return;
              }
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                );
              }
            });
          }
          final startIndex = (safePage - 1) * _pageSize;
          final pagedStudents = filteredStudents
              .skip(startIndex)
              .take(_pageSize)
              .toList();

          return RefreshIndicator(
            color: Colors.deepOrange,
            onRefresh: _refresh,
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                _SummaryHeader(data: data),
                const SizedBox(height: 14),
                _AdminStudentControls(
                  rankFilter: _rankFilter,
                  confidenceSort: _confidenceSort,
                  searchController: _searchController,
                  appliedSearch: _appliedSearch,
                  pageController: _pageController,
                  currentPage: safePage,
                  totalPages: totalPages,
                  totalCount: filteredStudents.length,
                  pageSize: _pageSize,
                  onRankChanged: (filter) {
                    setState(() {
                      _rankFilter = filter;
                      _setPage(1);
                    });
                  },
                  onSortChanged: (sort) {
                    setState(() {
                      _confidenceSort = sort;
                      _setPage(1);
                    });
                  },
                  onSearchSubmitted: _applySearch,
                  onClearSearch: _appliedSearch.isEmpty ? null : _clearSearch,
                  onPrevious: safePage > 1
                      ? () => _goToPage(safePage - 1, totalPages)
                      : null,
                  onNext: safePage < totalPages
                      ? () => _goToPage(safePage + 1, totalPages)
                      : null,
                  onPageSubmitted: () => _applyPageInput(totalPages),
                ),
                const SizedBox(height: 14),
                _RangeSelector(
                  selected: _range,
                  onChanged: (range) => setState(() => _range = range),
                ),
                const SizedBox(height: 14),
                _StressChart(students: filteredStudents, range: _range),
                const SizedBox(height: 16),
                for (final student in pagedStudents)
                  _StudentCard(
                    key: _studentCardKeys.putIfAbsent(
                      student.uid,
                      () => GlobalKey(),
                    ),
                    student: student,
                    range: _range,
                    highlighted: student.uid == widget.initialUserId,
                    onResolved: _refresh,
                  ),
                if (filteredStudents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: Text("No matching student data")),
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
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  "Admin guide",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  "Use this as a review aid. AI stress ranks are estimates and need human judgment before any action.",
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 14),
                _GuideSection(
                  title: "Stress rank",
                  children: [
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
                    const _GuideRow(
                      label: "<25",
                      value: "Low",
                      color: Colors.green,
                    ),
                  ],
                ),
                _GuideSection(
                  title: "Signal colors",
                  children: [
                    _GuideRow(
                      label: "Green",
                      value: "Balanced or highly positive",
                      color: Colors.green,
                    ),
                    _GuideRow(
                      label: "Yellow",
                      value: "A bit negative",
                      color: Colors.amber.shade700,
                    ),
                    _GuideRow(
                      label: "Red",
                      value: "Highly negative",
                      color: Colors.red,
                    ),
                  ],
                ),
                _GuideSection(
                  title: "Journal warnings",
                  children: [
                    _GuideRow(
                      label: "1.0",
                      value: "Critical self-harm or danger wording",
                      color: Colors.red,
                    ),
                    _GuideRow(
                      label: "0.65",
                      value: "Hopelessness, panic, depression, giving up",
                      color: Colors.deepOrange,
                    ),
                    _GuideRow(
                      label: "0.3",
                      value: "Normal stress words such as tired or burnout",
                      color: Colors.amber.shade700,
                    ),
                  ],
                ),
                _GuideNote(
                  icon: Icons.privacy_tip_outlined,
                  title: "Privacy",
                  text:
                      "Admin Monitoring shows contribution labels instead of exact step, mood, journal, or task counts. Only matched critical warning words or phrases are shown; full journal text is not sent to AI or admins.",
                ),
                _GuideNote(
                  icon: Icons.translate_rounded,
                  title: "Language support",
                  text:
                      "Local warning detection supports English and Philippine languages such as Tagalog, Cebuano, Ilocano, Hiligaynon, Waray, Kapampangan, Pangasinan, and Bicolano, then converts matches to privacy-safe English labels before scoring.",
                ),
                _GuideNote(
                  icon: Icons.insights_rounded,
                  title: "Mood and steps",
                  text:
                      "Mood index 0 means sad/high stress risk and 3 means happy/lower risk. A sad mood with high intensity raises risk. 4000 or more recorded average daily steps is highly positive.",
                ),
                _GuideNote(
                  icon: Icons.bar_chart_rounded,
                  title: "Chart",
                  text:
                      "The chart averages saved stress estimates for each day in the selected range. A dash means no stress estimate was saved for that day.",
                ),
              ],
            ),
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

class _AdminStudentControls extends StatelessWidget {
  const _AdminStudentControls({
    required this.rankFilter,
    required this.confidenceSort,
    required this.searchController,
    required this.appliedSearch,
    required this.pageController,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.pageSize,
    required this.onRankChanged,
    required this.onSortChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSubmitted,
  });

  final _StressRankFilter rankFilter;
  final _ConfidenceSort confidenceSort;
  final TextEditingController searchController;
  final String appliedSearch;
  final TextEditingController pageController;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final int pageSize;
  final ValueChanged<_StressRankFilter> onRankChanged;
  final ValueChanged<_ConfidenceSort> onSortChanged;
  final VoidCallback onSearchSubmitted;
  final VoidCallback? onClearSearch;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPageSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Expanded(
                child: Text(
                  "Student search",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Text(
                "$totalCount",
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearchSubmitted(),
            decoration: InputDecoration(
              labelText: "Search student",
              hintText: "Type name, email, or UID",
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: onSearchSubmitted,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text("Search"),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 112,
                minHeight: 42,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (onClearSearch != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.close_rounded),
                label: Text('Clear "$appliedSearch"'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            "Stress rank",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in _StressRankFilter.values)
                ChoiceChip(
                  label: Text(filter.label),
                  selected: rankFilter == filter,
                  selectedColor: filter.color.withValues(alpha: 0.16),
                  side: BorderSide(
                    color: rankFilter == filter
                        ? filter.color
                        : Colors.grey.shade300,
                  ),
                  labelStyle: TextStyle(
                    color: rankFilter == filter
                        ? filter.color
                        : Colors.grey.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                  onSelected: (_) => onRankChanged(filter),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Confidence priority",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<_ConfidenceSort>(
                  selected: {confidenceSort},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? Colors.deepOrange
                          : const Color(0xFFF7F8FC);
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? Colors.white
                          : Colors.black87;
                    }),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: _ConfidenceSort.descending,
                      label: Text("Descending"),
                    ),
                    ButtonSegment(
                      value: _ConfidenceSort.ascending,
                      label: Text("Ascending"),
                    ),
                  ],
                  onSelectionChanged: (value) => onSortChanged(value.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (totalPages > 1)
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text("Previous"),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: pageController,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onPageSubmitted(),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: "Page",
                      suffixText: "of $totalPages",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text("Next"),
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
    final average = points.where((point) => point.hasData).isEmpty
        ? 0.0
        : points
                  .where((point) => point.hasData)
                  .map((point) => point.value)
                  .reduce((a, b) => a + b) /
              points.where((point) => point.hasData).length;

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
              const Expanded(
                child: Text(
                  "Stress signal chart",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              _ChartSummaryPill(value: average, label: _rangeLabel(range)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Averages only saved stress estimates for each day.",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
                                    color: point.hasData
                                        ? _stressColor(point.value)
                                        : Colors.grey.shade300,
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
                          if (!point.hasData)
                            Text(
                              "-",
                              style: TextStyle(
                                color: Colors.grey.shade500,
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

class _ChartSummaryPill extends StatelessWidget {
  const _ChartSummaryPill({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = _stressColor(value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label avg ${value.toStringAsFixed(0)}",
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    super.key,
    required this.student,
    required this.range,
    required this.highlighted,
    required this.onResolved,
  });

  final _StudentWellnessSummary student;
  final _AdminRange range;
  final bool highlighted;
  final Future<void> Function() onResolved;

  Future<void> _contactStudent(BuildContext context) async {
    var phone = _normalizePhilippineMobile(student.contactPhoneNumber);

    if (phone == null) {
      final saved = await showDialog<_ContactInfo>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ContactInfoDialog(student: student),
      );
      if (saved == null || !context.mounted) return;
      phone = saved.phoneNumber;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri);
    if (launched || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the phone dialer')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _studentPoints(student, range);
    final hasActiveWarning =
        (student.warningSnippets.isNotEmpty ||
            student.warningJournals.isNotEmpty) &&
        !student.warningResolved;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: highlighted
            ? Border.all(color: Colors.deepOrange, width: 2)
            : null,
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Expanded(child: _StudentIdentityBlock(student: student)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _contactStudent(context),
                icon: const Icon(Icons.phone_rounded),
                label: const Text("Contact"),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasActiveWarning) ...[
            _WarningSnippetPanel(
              snippets: student.warningSnippets,
              onVerify: () => _openVerification(context),
            ),
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
                        color: point.hasData
                            ? _stressColor(point.value)
                            : Colors.grey.shade300,
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

  Future<void> _openVerification(BuildContext context) async {
    if (student.warningJournals.isEmpty && student.warningSignature.isEmpty) {
      return;
    }

    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _WarningVerificationScreen(
          student: student,
          onResolved: onResolved,
        ),
      ),
    );
  }
}

class _StudentIdentityBlock extends StatelessWidget {
  const _StudentIdentityBlock({required this.student});

  final _StudentWellnessSummary student;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          student.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 3),
        SelectableText(
          student.email.isEmpty ? student.uid : student.email,
          style: TextStyle(color: Colors.grey.shade600, height: 1.25),
        ),
        const SizedBox(height: 5),
        Text(
          'Status: ${_formatStatusTimestamp(student.aiUpdatedAt)}',
          softWrap: true,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _ContactInfoDialog extends StatefulWidget {
  const _ContactInfoDialog({required this.student});

  final _StudentWellnessSummary student;

  @override
  State<_ContactInfoDialog> createState() => _ContactInfoDialogState();
}

class _ContactInfoDialogState extends State<_ContactInfoDialog> {
  static const _relationships = [
    'Student',
    'Mother',
    'Father',
    'Guardian',
    'Sibling',
    'Relative',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  String _relationship = _relationships.first;
  bool _saving = false;
  bool _expanded = true;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _formKey.currentState?.validate() != true) return;

    final phone = _normalizePhilippineMobile(_phoneController.text);
    if (phone == null) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('admin_monitoring')
          .doc(widget.student.uid)
          .set({
            'contactPhoneNumber': phone,
            'contactRelationship': _relationship,
            'contactUpdatedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(
        context,
        _ContactInfo(phoneNumber: phone, relationship: _relationship),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save contact: ${error.code}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Add contact number',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.student.name} does not have a saved contact number. Add a Philippine mobile number before calling.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Philippine mobile number',
                    hintText: '09XXXXXXXXX or +639XXXXXXXXX',
                    prefixIcon: const Icon(Icons.phone_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  validator: (value) =>
                      _normalizePhilippineMobile(value) == null
                      ? 'Enter a valid Philippine mobile number.'
                      : null,
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExpansionTile(
                    initiallyExpanded: _expanded,
                    onExpansionChanged: (value) =>
                        setState(() => _expanded = value),
                    title: const Text(
                      'Whose number is this?',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    children: [
                      for (final relationship in _relationships)
                        ListTile(
                          enabled: !_saving,
                          onTap: _saving
                              ? null
                              : () {
                                  setState(() => _relationship = relationship);
                                },
                          title: Text(relationship),
                          trailing: _relationship == relationship
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.deepOrange,
                                )
                              : const Icon(Icons.circle_outlined),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('Save and call'),
          ),
        ],
      ),
    );
  }
}

class _ContactInfo {
  const _ContactInfo({required this.phoneNumber, required this.relationship});

  final String phoneNumber;
  final String relationship;
}

String? _normalizePhilippineMobile(String? raw) {
  final cleaned = (raw ?? '').replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (RegExp(r'^09\d{9}$').hasMatch(cleaned)) {
    return '+63${cleaned.substring(1)}';
  }
  if (RegExp(r'^\+639\d{9}$').hasMatch(cleaned)) {
    return cleaned;
  }
  if (RegExp(r'^639\d{9}$').hasMatch(cleaned)) {
    return '+$cleaned';
  }
  return null;
}

class _WarningSnippetPanel extends StatelessWidget {
  const _WarningSnippetPanel({required this.snippets, required this.onVerify});

  final List<String> snippets;
  final Future<void> Function() onVerify;

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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onVerify,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text("Verify warning"),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningVerificationScreen extends StatefulWidget {
  const _WarningVerificationScreen({
    required this.student,
    required this.onResolved,
  });

  final _StudentWellnessSummary student;
  final Future<void> Function() onResolved;

  @override
  State<_WarningVerificationScreen> createState() =>
      _WarningVerificationScreenState();
}

class _WarningVerificationScreenState
    extends State<_WarningVerificationScreen> {
  late List<_WarningJournalReview> _visibleWarnings;
  final Set<String> _savingSignatures = <String>{};

  @override
  void initState() {
    super.initState();
    _visibleWarnings = _initialUnresolvedWarnings();
  }

  List<_WarningJournalReview> _initialUnresolvedWarnings() {
    final resolved = <String>{
      if (widget.student.resolvedWarningSignature.isNotEmpty)
        widget.student.resolvedWarningSignature,
    };
    final source = widget.student.warningJournals.isNotEmpty
        ? widget.student.warningJournals
        : [
            _WarningJournalReview(
              id: widget.student.warningJournalId,
              signature: widget.student.warningSignature,
              text: widget.student.warningJournalText,
              createdAt: widget.student.warningJournalCreatedAt,
              snippets: widget.student.warningSnippets,
              severity: 'critical',
            ),
          ];

    return source
        .where(
          (warning) =>
              warning.signature.isNotEmpty &&
              !resolved.contains(warning.signature),
        )
        .toList();
  }

  Future<void> _markJournalResolved(
    _WarningJournalReview warning, {
    bool falsePositive = false,
  }) async {
    if (_savingSignatures.contains(warning.signature) ||
        warning.signature.isEmpty) {
      return;
    }
    setState(() => _savingSignatures.add(warning.signature));

    try {
      final remaining = _visibleWarnings
          .where((item) => item.signature != warning.signature)
          .toList();
      final allResolved = remaining.isEmpty;
      final resolvedState = _resolvedAiStateForRemainingWarnings(remaining);
      final primaryWarning = remaining.isEmpty ? null : remaining.first;
      final todayKey = _todayKey();

      await FirebaseFirestore.instance
          .collection('admin_monitoring')
          .doc(widget.student.uid)
          .set({
            'resolvedWarningSignature': warning.signature,
            'resolvedWarningSignatures': FieldValue.arrayUnion([
              warning.signature,
            ]),
            'resolvedWarningAt': FieldValue.serverTimestamp(),
            'warningJournals': remaining.map((item) => item.toJson()).toList(),
            'stressScore': resolvedState.stressScore,
            'stressRank': resolvedState.stressRank,
            'confidence': resolvedState.confidence,
            'aiMoodIndex': resolvedState.moodIndex,
            'aiMoodIntensity': resolvedState.moodIntensity,
            'aiMoodStatus': resolvedState.aiMoodStatus,
            'aiMoodStatusUpdatedAt': FieldValue.serverTimestamp(),
            'rationale': resolvedState.rationale,
            'supportResolutionStatus': falsePositive
                ? 'false_positive'
                : 'support_provided',
            'supportResolutionType': falsePositive
                ? 'false_positive'
                : 'support_provided',
            'supportResolutionNote': falsePositive
                ? 'Admin verified this warning as a false positive.'
                : 'Admin verified this warning after support was provided.',
            'supportResolutionUpdatedAt': FieldValue.serverTimestamp(),
            'stressHistory.$todayKey': resolvedState.stressScore,
            'updatedAt': FieldValue.serverTimestamp(),
            if (!allResolved && primaryWarning != null) ...{
              'warningSnippets': primaryWarning.snippets,
              'warningFindings': remaining
                  .map(
                    (item) => {
                      'journalId': item.id,
                      'signature': item.signature,
                      'severity': item.severity,
                      'snippets': item.snippets,
                    },
                  )
                  .toList(),
              'warningSignature': primaryWarning.signature,
              'warningJournalId': primaryWarning.id,
              'warningJournalText': primaryWarning.text,
              'warningJournalCreatedAt': primaryWarning.createdAt,
              'journalWarningWeight': resolvedState.warningWeight,
              'journalWarningSeverity': primaryWarning.severity,
              'hasDangerWarning': resolvedState.hasDangerWarning,
            },
            if (allResolved) ...{
              'warningSnippets': <String>[],
              'warningFindings': <Map<String, dynamic>>[],
              'warningSignature': '',
              'warningJournalId': '',
              'warningJournalText': '',
              'warningJournalCreatedAt': '',
              'journalWarningWeight': 0.0,
              'journalWarningSeverity': 'none',
              'hasDangerWarning': false,
            },
          }, SetOptions(merge: true));
      await AdminAlertService.markResolvedForSignature(
        userId: widget.student.uid,
        warningSignature: warning.signature,
      );
      await widget.onResolved();

      if (!mounted) return;
      setState(() {
        _visibleWarnings = remaining;
      });
      _showAdminFeedback(
        title: "Warning verified",
        message: allResolved
            ? falsePositive
                  ? "All active journal warnings were marked as false positive. The user's AI analysis has been updated."
                  : "All active critical journal warnings were resolved. The user's AI analysis has been updated."
            : falsePositive
            ? "This journal warning was marked as false positive. Remaining active warnings still need review."
            : "This journal warning was resolved. Remaining active warnings still need review.",
        color: falsePositive ? Colors.blue : Colors.green,
      );
      if (allResolved) Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() => _savingSignatures.remove(warning.signature));
      }
    }
  }

  _ResolvedAiState _resolvedAiStateForRemainingWarnings(
    List<_WarningJournalReview> remaining,
  ) {
    if (remaining.isEmpty) {
      return const _ResolvedAiState(
        stressScore: 0,
        stressRank: 'Low',
        confidence: 0,
        moodIndex: 2,
        moodIntensity: 0.35,
        warningWeight: 0,
        hasDangerWarning: false,
        aiMoodStatus: 'Support was provided',
        rationale: [
          'Support was provided',
          'admin verified the warning as resolved',
          'fresh signals will guide the next analysis',
        ],
      );
    }

    final highest = remaining.reduce((current, next) {
      return _severityPriority(next.severity) >
              _severityPriority(current.severity)
          ? next
          : current;
    });

    switch (_normalizedSeverity(highest.severity)) {
      case 'critical':
        return const _ResolvedAiState(
          stressScore: 88,
          stressRank: 'High',
          confidence: 0.86,
          moodIndex: 0,
          moodIntensity: 0.88,
          warningWeight: 1,
          hasDangerWarning: true,
          aiMoodStatus: 'Active critical warning still needs review',
          rationale: [
            'another critical journal warning remains active',
            'admin verification still pending',
          ],
        );
      case 'elevated':
      case 'high':
        return const _ResolvedAiState(
          stressScore: 68,
          stressRank: 'Elevated',
          confidence: 0.74,
          moodIndex: 1,
          moodIntensity: 0.68,
          warningWeight: 0.72,
          hasDangerWarning: false,
          aiMoodStatus: 'Active elevated warning still needs review',
          rationale: [
            'another elevated journal warning remains active',
            'admin verification still pending',
          ],
        );
      case 'moderate':
      case 'warning':
        return const _ResolvedAiState(
          stressScore: 46,
          stressRank: 'Moderate',
          confidence: 0.62,
          moodIndex: 1,
          moodIntensity: 0.52,
          warningWeight: 0.45,
          hasDangerWarning: false,
          aiMoodStatus: 'Moderate journal warning still needs review',
          rationale: [
            'another journal warning remains active',
            'admin verification still pending',
          ],
        );
      default:
        return const _ResolvedAiState(
          stressScore: 24,
          stressRank: 'Low',
          confidence: 0.48,
          moodIndex: 2,
          moodIntensity: 0.38,
          warningWeight: 0.2,
          hasDangerWarning: false,
          aiMoodStatus: 'Lower-risk warning still needs review',
          rationale: [
            'a lower-risk journal warning remains active',
            'admin verification still pending',
          ],
        );
    }
  }

  static int _severityPriority(String severity) {
    switch (_normalizedSeverity(severity)) {
      case 'critical':
        return 4;
      case 'elevated':
      case 'high':
        return 3;
      case 'moderate':
      case 'warning':
        return 2;
      case 'low':
        return 1;
      default:
        return 0;
    }
  }

  static String _normalizedSeverity(String severity) {
    return severity.trim().toLowerCase();
  }

  static String _todayKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> _showAdminFeedback({
    required String title,
    required String message,
    required Color color,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.verified_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(message, style: const TextStyle(height: 1.4)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Done"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final warnings = _visibleWarnings;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text("Verify Warning"),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.student.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            widget.student.email.isEmpty
                                ? widget.student.uid
                                : widget.student.email,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (warnings.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "No unresolved journal warnings remain.",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final warning in warnings) ...[
                  const Text(
                    "Unresolved journal warning",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final snippet in warning.snippets)
                        Chip(
                          label: Text(snippet),
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                          side: BorderSide.none,
                          labelStyle: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Text(
                      warning.text.trim().isEmpty
                          ? "Raw journal text is unavailable. The student may not have consented to raw AI data sharing yet."
                          : warning.text,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (warning.createdAt.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      "Created: ${warning.createdAt}",
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _savingSignatures.contains(warning.signature)
                        ? null
                        : () => _markJournalResolved(warning),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: _savingSignatures.contains(warning.signature)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.verified_rounded),
                    label: Text(
                      _savingSignatures.contains(warning.signature)
                          ? "Resolving..."
                          : "Mark this warning resolved",
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _savingSignatures.contains(warning.signature)
                        ? null
                        : () => _markJournalResolved(
                            warning,
                            falsePositive: true,
                          ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text("False positive"),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
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
                "$readySignals/${features.totalSignalCount}",
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
                value: features.moodContributionLabel,
                color: features.moodContributionColor,
              ),
              _SignalChip(
                label: "Steps",
                ready: features.hasStepSignal,
                value: features.stepsContributionLabel,
                color: features.stepsContributionColor,
              ),
              _SignalChip(
                label: "Journal",
                ready: features.hasJournalSignal,
                value: features.journalContributionLabel,
                color: features.journalContributionColor,
              ),
              _SignalChip(
                label: "Warning",
                ready: true,
                value: features.journalWarningLabel,
                color: features.journalWarningColor,
                icon: features.journalWarningIcon,
              ),
              _SignalChip(
                label: "Tasks",
                ready: features.hasTaskSignal,
                value: features.taskContributionLabel,
                color: features.taskContributionColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: "AI rank",
                  value: features.modelResult.confidence <= 0
                      ? "Pending"
                      : features.modelResult.score.toStringAsFixed(0),
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
    this.color,
    this.icon,
  });

  final String label;
  final bool ready;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? (ready ? Colors.green : Colors.grey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ??
                (ready
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked),
            color: chipColor,
            size: 15,
          ),
          const SizedBox(width: 5),
          Text(
            "$label $value",
            style: TextStyle(
              color: chipColor,
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
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _GuideNote extends StatelessWidget {
  const _GuideNote({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.deepOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
              ],
            ),
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
    required this.contactPhoneNumber,
    required this.contactRelationship,
    required this.photoUrl,
    required this.aiUpdatedAt,
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
    required this.warningSignature,
    required this.resolvedWarningSignature,
    required this.warningJournals,
    required this.warningJournalId,
    required this.warningJournalText,
    required this.warningJournalCreatedAt,
    required this.mlFeatures,
  });

  final String uid;
  final String name;
  final String email;
  final String contactPhoneNumber;
  final String contactRelationship;
  final String? photoUrl;
  final DateTime? aiUpdatedAt;
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
  final String warningSignature;
  final String resolvedWarningSignature;
  final List<_WarningJournalReview> warningJournals;
  final String warningJournalId;
  final String warningJournalText;
  final String warningJournalCreatedAt;
  final _PersonalMlFeatures mlFeatures;

  bool get warningResolved {
    if (resolvedWarningSignature.isEmpty) return false;
    return warningSignature.isEmpty ||
        warningSignature == resolvedWarningSignature;
  }

  String get normalizedStressRank {
    final normalized = stressRank.trim().toLowerCase();
    if (normalized == 'resolved') return 'Resolved';
    if (normalized == 'high') return 'High';
    if (normalized == 'elevated') return 'Elevated';
    if (normalized == 'moderate') return 'Moderate';
    return 'Low';
  }
}

class _WarningJournalReview {
  const _WarningJournalReview({
    required this.id,
    required this.signature,
    required this.text,
    required this.createdAt,
    required this.snippets,
    required this.severity,
  });

  final String id;
  final String signature;
  final String text;
  final String createdAt;
  final List<String> snippets;
  final String severity;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'signature': signature,
      'text': text,
      'createdAt': createdAt,
      'snippets': snippets,
      'severity': severity,
    };
  }
}

class _ResolvedAiState {
  const _ResolvedAiState({
    required this.stressScore,
    required this.stressRank,
    required this.confidence,
    required this.moodIndex,
    required this.moodIntensity,
    required this.warningWeight,
    required this.hasDangerWarning,
    required this.aiMoodStatus,
    required this.rationale,
  });

  final double stressScore;
  final String stressRank;
  final double confidence;
  final int moodIndex;
  final double moodIntensity;
  final double warningWeight;
  final bool hasDangerWarning;
  final String aiMoodStatus;
  final List<String> rationale;
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

  int get totalSignalCount => 5;

  int get totalTaskCount =>
      activeTaskCount + completedTaskCount + overdueTaskCount;

  String get journalWarningLabel {
    if (journalWarningWeight <= 0) return 'None';
    if (journalWarningSeverity == 'critical') return 'Critical';
    if (journalWarningSeverity == 'elevated') return 'Elevated';
    return 'Stress';
  }

  String get moodContributionLabel {
    if (!hasMoodSignal) return 'No data';
    if (avgMoodIndex <= 0.5 && avgMoodIntensity >= 0.8) {
      return 'Highly negative';
    }
    if (avgMoodIndex <= 1.5) return 'A bit negative';
    return 'Balanced';
  }

  Color get journalWarningColor {
    if (journalWarningWeight <= 0) return Colors.green;
    if (journalWarningSeverity == 'critical') return Colors.red;
    return Colors.amber.shade800;
  }

  Color get moodContributionColor {
    if (!hasMoodSignal) return Colors.grey;
    if (avgMoodIndex <= 0.5 && avgMoodIntensity >= 0.8) return Colors.red;
    if (avgMoodIndex <= 1.5) return Colors.amber.shade800;
    return Colors.green;
  }

  String get stepsContributionLabel {
    if (!hasStepSignal) return 'No data';
    if (avgDailySteps < 1500) return 'Highly negative';
    if (avgDailySteps < 4000) return 'A bit negative';
    return 'Highly positive';
  }

  Color get stepsContributionColor {
    if (!hasStepSignal) return Colors.grey;
    if (avgDailySteps < 1500) return Colors.red;
    if (avgDailySteps < 4000) return Colors.amber.shade800;
    return Colors.green;
  }

  String get journalContributionLabel {
    if (!hasJournalSignal) return 'No data';
    if (journalEntryCount >= 12) return 'A bit negative';
    return 'Balanced';
  }

  Color get journalContributionColor {
    if (!hasJournalSignal) return Colors.grey;
    if (journalEntryCount >= 12) return Colors.amber.shade800;
    return Colors.green;
  }

  String get taskContributionLabel {
    if (!hasTaskSignal) return 'No data';
    if (overdueTaskCount >= 3) return 'Highly negative';
    if (overdueTaskCount > 0 || activeTaskCount >= 8) {
      return 'A bit negative';
    }
    return 'Balanced';
  }

  Color get taskContributionColor {
    if (!hasTaskSignal) return Colors.grey;
    if (overdueTaskCount >= 3) return Colors.red;
    if (overdueTaskCount > 0 || activeTaskCount >= 8) {
      return Colors.amber.shade800;
    }
    return Colors.green;
  }

  IconData get journalWarningIcon {
    if (journalWarningWeight <= 0) return Icons.check_circle_rounded;
    if (journalWarningSeverity == 'critical') {
      return Icons.warning_amber_rounded;
    }
    return Icons.error_outline_rounded;
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
  const _ChartPoint({
    required this.label,
    required this.value,
    required this.count,
  });

  final String label;
  final double value;
  final int count;

  bool get hasData => count > 0;
}

enum _AdminRange { week, month }

enum _StressRankFilter { all, high, elevated, moderate, low }

extension _StressRankFilterLabel on _StressRankFilter {
  String get label {
    switch (this) {
      case _StressRankFilter.all:
        return 'All';
      case _StressRankFilter.high:
        return 'High';
      case _StressRankFilter.elevated:
        return 'Elevated';
      case _StressRankFilter.moderate:
        return 'Moderate';
      case _StressRankFilter.low:
        return 'Low';
    }
  }

  Color get color {
    switch (this) {
      case _StressRankFilter.all:
        return Colors.blueGrey;
      case _StressRankFilter.high:
        return Colors.red;
      case _StressRankFilter.elevated:
        return Colors.deepOrange;
      case _StressRankFilter.moderate:
        return Colors.amber;
      case _StressRankFilter.low:
        return Colors.green;
    }
  }
}

enum _ConfidenceSort { ascending, descending }

List<_ChartPoint> _aggregateStress(
  List<_StudentWellnessSummary> students,
  _AdminRange range,
) {
  if (students.isEmpty) return const [];

  final keys = students.first.dailyStress.keys.toList();
  final scopedKeys = _keysForRange(keys, range);

  return scopedKeys.map((key) {
    final values = students
        .where((student) => student.dailyStress.containsKey(key))
        .map((student) => student.dailyStress[key] ?? 0)
        .toList();
    final average = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a + b) / values.length;

    return _ChartPoint(
      label: _shortLabel(key, range),
      value: average,
      count: values.length,
    );
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
          count: student.dailyStress.containsKey(key) ? 1 : 0,
        ),
      )
      .toList();
}

List<String> _keysForRange(List<String> keys, _AdminRange range) {
  if (keys.isEmpty) return const [];

  switch (range) {
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
  final name = DisplayNameService.cleanForDisplay(
    data['name'] as String?,
    fallback: '',
  );
  if (name.isNotEmpty) return name;

  final email = DisplayNameService.normalize(data['email'] as String?);
  if (email.isNotEmpty) {
    return DisplayNameService.cleanForDisplay(
      email.split('@').first,
      fallback: 'Student',
    );
  }

  return 'Student';
}

DateTime? _timestampFromData(Map<String, dynamic> data) {
  final value = data['aiMoodStatusUpdatedAt'] ?? data['updatedAt'];
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _formatStatusTimestamp(DateTime? value) {
  if (value == null) return 'waiting for AI update';
  final manila = value.toUtc().add(const Duration(hours: 8));
  final hour = manila.hour > 12
      ? manila.hour - 12
      : manila.hour == 0
      ? 12
      : manila.hour;
  final minute = manila.minute.toString().padLeft(2, '0');
  final second = manila.second.toString().padLeft(2, '0');
  final period = manila.hour >= 12 ? 'PM' : 'AM';
  return '${manila.year}-${manila.month.toString().padLeft(2, '0')}-${manila.day.toString().padLeft(2, '0')} $hour:$minute:$second $period';
}

String _shortLabel(String key, _AdminRange range) {
  final parts = key.split('-');
  if (parts.length != 3) return key;

  if (range == _AdminRange.month) {
    return parts[2];
  }

  return "${parts[1]}/${parts[2]}";
}

String _rangeLabel(_AdminRange range) {
  switch (range) {
    case _AdminRange.week:
      return 'Week';
    case _AdminRange.month:
      return 'Month';
  }
}

String _dateKey(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}
