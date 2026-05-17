import 'package:flutter/material.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final leaders = [
      {
        "name": "Sophia",
        "streak": 28,
        "steps": 124500,
        "rank": 1,
      },
      {
        "name": "Daniel",
        "streak": 24,
        "steps": 117200,
        "rank": 2,
      },
      {
        "name": "Olivia",
        "streak": 19,
        "steps": 101300,
        "rank": 3,
      },
      {
        "name": "You",
        "streak": 15,
        "steps": 84500,
        "rank": 4,
      },
      {
        "name": "Lucas",
        "streak": 12,
        "steps": 79200,
        "rank": 5,
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,

        title: const Text(
          "Leaderboard",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            /// HEADER CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),

              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.shade300,
                    Colors.deepOrange.shade400,
                  ],
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

                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              "Streak Champions",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),

                            SizedBox(height: 4),

                            Text(
                              "Top active students this month",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
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
                      _headerStat("Your Rank", "#4"),
                      _headerStat("Current Streak", "15"),
                      _headerStat("Monthly Steps", "84K"),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            /// PODIUM
            const Text(
              "Top Performers",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,

              children: [
                _buildPodium(
                  rank: 2,
                  name: "Daniel",
                  streak: 24,
                  height: 120,
                  color: Colors.grey.shade400,
                ),

                const SizedBox(width: 14),

                _buildPodium(
                  rank: 1,
                  name: "Sophia",
                  streak: 28,
                  height: 165,
                  color: Colors.orange,
                  crown: true,
                ),

                const SizedBox(width: 14),

                _buildPodium(
                  rank: 3,
                  name: "Olivia",
                  streak: 19,
                  height: 100,
                  color: Colors.brown.shade300,
                ),
              ],
            ),

            const SizedBox(height: 34),

            const Text(
              "Global Rankings",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 18),

            ...leaders.map((user) {
              final isYou = user['name'] == 'You';

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: isYou
                      ? Colors.orange.shade100
                      : Colors.white,

                  borderRadius: BorderRadius.circular(22),

                  border: isYou
                      ? Border.all(
                          color: Colors.deepOrange,
                          width: 1.5,
                        )
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
                        '#${user['rank']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.orange.shade300,

                      child: Text(
                        user['name'].toString()[0],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            user['name'].toString(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '${user['steps']} total steps',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),

                      decoration: BoxDecoration(
                        color: Colors.deepOrange.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),

                      child: Row(
                        children: [
                          const Text('🔥'),
                          const SizedBox(width: 6),
                          Text(
                            '${user['streak']}',
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
            }),
          ],
        ),
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
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  static Widget _buildPodium({
    required int rank,
    required String name,
    required int streak,
    required double height,
    required Color color,
    bool crown = false,
  }) {
    return Column(
      children: [
        if (crown)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '👑',
              style: TextStyle(fontSize: 28),
            ),
          ),

        CircleAvatar(
          radius: 30,
          backgroundColor: color,

          child: Text(
            name[0],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(height: 10),

        Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          '🔥 $streak',
          style: TextStyle(
            color: Colors.orange.shade800,
            fontWeight: FontWeight.w600,
          ),
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
            '#$rank',
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