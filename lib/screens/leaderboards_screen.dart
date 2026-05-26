import 'package:flutter/material.dart';
import '../services/leaderboard_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late Future<LeaderboardResult> _leaderboard;

  @override
  void initState() {
    super.initState();
    _leaderboard = LeaderboardService.loadMonthlyLeaderboard();
  }

  Future<void> _refresh() async {
    final next = LeaderboardService.loadMonthlyLeaderboard();
    setState(() => _leaderboard = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          "Leaderboard",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
      body: FutureBuilder<LeaderboardResult>(
        future: _leaderboard,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.deepOrange),
            );
          }

          if (snapshot.hasError) {
            return _ErrorState(onRetry: _refresh);
          }

          final data = snapshot.data;
          if (data == null || data.entries.isEmpty) {
            return _EmptyState(onRefresh: _refresh);
          }

          return RefreshIndicator(
            color: Colors.deepOrange,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _HeaderCard(data: data),
                const SizedBox(height: 30),
                const Text(
                  "Top Performers",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                _Podium(entries: data.podium),
                const SizedBox(height: 34),
                const Text(
                  "Global Rankings",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                ...data.entries.map((entry) => _RankingTile(entry)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.data});

  final LeaderboardResult data;

  @override
  Widget build(BuildContext context) {
    final current = data.currentUser;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade300, Colors.deepOrange.shade400],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Your Streak Rank",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Your wellness streak standing this ${data.monthLabel}",
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _headerStat("Your Rank", current == null ? "-" : "#${current.rank}"),
              _headerStat("Points", _compact(current?.streakPoints ?? 0)),
              _headerStat("Step Streak", "${current?.stepStreak ?? 0}d"),
              _headerStat("Mood Streak", "${current?.moodStreak ?? 0}d"),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _headerStat(String title, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final first = entries.isNotEmpty ? entries[0] : null;
    final second = entries.length > 1 ? entries[1] : null;
    final third = entries.length > 2 ? entries[2] : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _PodiumBlock(
          entry: second,
          height: 120,
          color: Colors.grey.shade400,
        ),
        const SizedBox(width: 14),
        _PodiumBlock(
          entry: first,
          height: 165,
          color: Colors.orange,
          crown: true,
        ),
        const SizedBox(width: 14),
        _PodiumBlock(
          entry: third,
          height: 100,
          color: Colors.brown.shade300,
        ),
      ],
    );
  }
}

class _PodiumBlock extends StatelessWidget {
  const _PodiumBlock({
    required this.entry,
    required this.height,
    required this.color,
    this.crown = false,
  });

  final LeaderboardEntry? entry;
  final double height;
  final Color color;
  final bool crown;

  @override
  Widget build(BuildContext context) {
    final name = entry?.name ?? "-";
    final rank = entry?.rank ?? 0;

    return Column(
      children: [
        if (crown)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Icon(Icons.workspace_premium_rounded, color: Colors.orange),
          ),
        _Avatar(entry: entry, radius: 30, color: color),
        const SizedBox(height: 10),
        SizedBox(
          width: 86,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 18,
              color: entry == null ? Colors.grey : Colors.deepOrange,
            ),
            const SizedBox(width: 4),
            Text(
              entry == null ? "-" : "${entry?.streakPoints}",
              style: TextStyle(
                color: entry == null
                    ? Colors.grey.shade600
                    : Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: 88,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(
            rank == 0 ? "-" : "#$rank",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile(this.entry);

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: entry.isCurrentUser ? Colors.orange.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: entry.isCurrentUser
            ? Border.all(color: Colors.deepOrange, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Text(
              '#${entry.rank}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          _Avatar(entry: entry, radius: 24, color: Colors.orange.shade300),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isCurrentUser ? "${entry.name} (You)" : entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.monthlySteps} total steps',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 18,
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 6),
                Text(
                  '${entry.streakPoints}',
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold,
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

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.entry,
    required this.radius,
    required this.color,
  });

  final LeaderboardEntry? entry;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final photoUrl = entry?.photoUrl;
    final name = entry?.name ?? "-";

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
          ? NetworkImage(photoUrl)
          : null,
      child: photoUrl == null || photoUrl.isEmpty
          ? Text(
              (name.isEmpty ? "-" : name[0]).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Colors.deepOrange,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.emoji_events_outlined, size: 56, color: Colors.deepOrange),
          SizedBox(height: 16),
          Text(
            "No rankings yet",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            "Streak points will appear here after students save mood and step progress.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
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
      child: ElevatedButton.icon(
        onPressed: () {
          onRetry();
        },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text("Retry leaderboard"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

String _compact(int value) {
  if (value >= 1000000) {
    return "${(value / 1000000).toStringAsFixed(1)}M";
  }
  if (value >= 1000) {
    return "${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K";
  }

  return value.toString();
}
