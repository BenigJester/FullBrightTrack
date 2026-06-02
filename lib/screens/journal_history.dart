import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_data.dart';
import '../services/journal_service.dart';

class JournalHistoryScreen extends StatefulWidget {
  const JournalHistoryScreen({super.key});

  @override
  State<JournalHistoryScreen> createState() => _JournalHistoryScreenState();
}

class _JournalHistoryScreenState extends State<JournalHistoryScreen> {
  static const primaryColor = Color(0xFFFF7A59);
  static const backgroundColor = Color(0xFFFFFBFA);
  static const textPrimary = Color(0xFF2D2D2D);
  static const int pageSize = 100;

  String selectedFilter = "All";
  bool filtersExpanded = false;
  bool sortDescending = true;
  int currentPage = 1;
  DateTime? startDate;
  DateTime? endDate;
  final TextEditingController _pageController = TextEditingController(
    text: '1',
  );

  final filters = [
    "All",
    "Stress",
    "Happy",
    "Productive",
    "Tired",
    "Motivated",
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshHistory() async {
    await JournalService.initialize(context.read<AppData>());
  }

  @override
  Widget build(BuildContext context) {
    final appData = context.watch<AppData>();

    List<Map<String, dynamic>> journals = List<Map<String, dynamic>>.from(
      appData.journals,
    );

    // ================= FILTER =================

    if (selectedFilter != "All") {
      journals = journals.where((j) => j["tag"] == selectedFilter).toList();
    }

    if (startDate != null || endDate != null) {
      journals = journals.where((journal) {
        final date = (journal["created_at"] as Timestamp?)?.toDate();
        if (date == null) return false;
        final afterStart =
            startDate == null ||
            !DateTime(date.year, date.month, date.day).isBefore(startDate!);
        final beforeEnd =
            endDate == null ||
            !DateTime(date.year, date.month, date.day).isAfter(endDate!);
        return afterStart && beforeEnd;
      }).toList();
    }

    // ================= SORT NEWEST =================

    journals.sort((a, b) {
      final aDate = (a["created_at"] as Timestamp?)?.toDate() ?? DateTime.now();

      final bDate = (b["created_at"] as Timestamp?)?.toDate() ?? DateTime.now();

      return sortDescending ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
    });

    final totalPages = (journals.length / pageSize).ceil().clamp(1, 999999);
    if (currentPage > totalPages) {
      currentPage = totalPages;
      _pageController.text = '$currentPage';
    }
    final firstIndex = (currentPage - 1) * pageSize;
    final visibleJournals = journals.skip(firstIndex).take(pageSize).toList();

    return Scaffold(
      backgroundColor: backgroundColor,

      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),

          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: const Text(
          "Journal History",
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
        ),

        centerTitle: false,
      ),

      body: RefreshIndicator(
        color: primaryColor,
        onRefresh: _refreshHistory,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // ================= FILTERS =================
            SliverToBoxAdapter(
              child: _filterPanel(totalCount: journals.length),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 14)),

            // ================= BODY =================
            if (appData.journalLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (journals.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _emptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (journals.length > pageSize) _managementCard(),
                    for (final journal in visibleJournals)
                      _journalCard(journal),
                    if (journals.length > pageSize)
                      _pagination(totalPages: totalPages),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterPanel({required int totalCount}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.orange.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => filtersExpanded = !filtersExpanded),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$selectedFilter • ${sortDescending ? "Newest first" : "Oldest first"} • $totalCount",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Icon(
                    filtersExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                ],
              ),
            ),
            if (filtersExpanded) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in filters)
                    ChoiceChip(
                      label: Text(filter),
                      selected: selectedFilter == filter,
                      onSelected: (_) => setState(() {
                        selectedFilter = filter;
                        _setPage(1);
                      }),
                      selectedColor: const Color(0xFFFFD8CC),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text("Descending"),
                    icon: Icon(Icons.south_rounded),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text("Ascending"),
                    icon: Icon(Icons.north_rounded),
                  ),
                ],
                selected: {sortDescending},
                onSelectionChanged: (value) => setState(() {
                  sortDescending = value.first;
                  _setPage(1);
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(start: true),
                      icon: const Icon(Icons.event_rounded),
                      label: Text(_dateLabel(startDate, "Start date")),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(start: false),
                      icon: const Icon(Icons.event_available_rounded),
                      label: Text(_dateLabel(endDate, "End date")),
                    ),
                  ),
                ],
              ),
              if (startDate != null || endDate != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    startDate = null;
                    endDate = null;
                    _setPage(1);
                  }),
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text("Clear date filter"),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: start
          ? startDate ?? DateTime.now()
          : endDate ?? startDate ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      final normalized = DateTime(picked.year, picked.month, picked.day);
      if (start) {
        startDate = normalized;
        if (endDate != null && endDate!.isBefore(startDate!)) {
          endDate = startDate;
        }
      } else {
        endDate = normalized;
        if (startDate != null && startDate!.isAfter(endDate!)) {
          startDate = endDate;
        }
      }
      _setPage(1);
    });
  }

  String _dateLabel(DateTime? date, String fallback) {
    if (date == null) return fallback;
    return "${date.month}/${date.day}/${date.year}";
  }

  void _setPage(int page) {
    currentPage = page;
    _pageController.text = '$currentPage';
  }

  Widget _pagination({required int totalPages}) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: _historyCardDecoration(),
      child: Row(
        children: [
          IconButton(
            onPressed: currentPage <= 1
                ? null
                : () => setState(() => _setPage(currentPage - 1)),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: TextField(
              controller: _pageController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                suffixText: "of $totalPages",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onSubmitted: (value) {
                final page = int.tryParse(value.trim()) ?? currentPage;
                setState(() => _setPage(page.clamp(1, totalPages)));
              },
            ),
          ),
          IconButton(
            onPressed: currentPage >= totalPages
                ? null
                : () => setState(() => _setPage(currentPage + 1)),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _managementCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: _historyCardDecoration(),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.inventory_2_rounded, color: primaryColor),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Tip: when your history gets large, review older entries monthly, export important reflections, and delete entries you no longer need to keep the app easier to browse.",
              style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _historyCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.orange.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  // ================= EMPTY =================

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              padding: const EdgeInsets.all(28),

              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),

              child: Icon(
                Icons.auto_stories_rounded,
                size: 58,
                color: Colors.orange.shade300,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "No Journal Entries",
              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              "Your reflections and memories will appear here.",
              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= JOURNAL CARD =================

  Widget _journalCard(Map<String, dynamic> journal) {
    final timestamp = journal["created_at"] as Timestamp?;

    final date = timestamp?.toDate();

    final tag = journal["tag"] ?? "";

    return Container(
      margin: const EdgeInsets.only(bottom: 18),

      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(30),

        border: Border.all(color: Colors.orange.shade100),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // ================= HEADER =================
          Row(
            children: [
              if (tag.toString().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),

                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE2D8),

                    borderRadius: BorderRadius.circular(30),
                  ),

                  child: Text(
                    tag,

                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                ),

              const Spacer(),

              Text(
                date != null ? "${date.month}/${date.day}/${date.year}" : "",

                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ================= TEXT =================
          Text(
            journal["text"] ?? "",

            style: const TextStyle(
              fontSize: 16,
              height: 1.8,
              color: textPrimary,
            ),
          ),

          // ================= PROMPT =================
          if ((journal["prompt"] ?? "").toString().isNotEmpty) ...[
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),

              decoration: BoxDecoration(
                color: const Color(0xFFFFF6F2),

                borderRadius: BorderRadius.circular(18),
              ),

              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  const Text("\u{1F9E0}", style: TextStyle(fontSize: 18)),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      journal["prompt"] ?? "",

                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
