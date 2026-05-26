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

  String selectedFilter = "All";

  final filters = [
    "All",
    "Stress",
    "Happy",
    "Productive",
    "Tired",
    "Motivated",
  ];

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

    // ================= SORT NEWEST =================

    journals.sort((a, b) {
      final aDate = (a["created_at"] as Timestamp?)?.toDate() ?? DateTime.now();

      final bDate = (b["created_at"] as Timestamp?)?.toDate() ?? DateTime.now();

      return bDate.compareTo(aDate);
    });

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
              child: SizedBox(
                height: 54,

                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),

                  scrollDirection: Axis.horizontal,

                  itemBuilder: (_, index) {
                    final filter = filters[index];

                    final isSelected = selectedFilter == filter;

                    return ChoiceChip(
                      label: Text(filter),

                      selected: isSelected,

                      onSelected: (_) {
                        setState(() {
                          selectedFilter = filter;
                        });
                      },

                      selectedColor: const Color(0xFFFFD8CC),

                      backgroundColor: Colors.white,

                      side: BorderSide(
                        color: isSelected
                            ? primaryColor
                            : Colors.orange.shade100,
                      ),

                      labelStyle: TextStyle(
                        color: isSelected ? primaryColor : Colors.grey.shade700,

                        fontWeight: FontWeight.w600,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    );
                  },

                  separatorBuilder: (_, _) => const SizedBox(width: 10),

                  itemCount: filters.length,
                ),
              ),
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
                sliver: SliverList.builder(
                  itemCount: journals.length,
                  itemBuilder: (context, index) {
                    final journal = journals[index];

                    return _journalCard(journal);
                  },
                ),
              ),
          ],
        ),
      ),
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
