import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'more_screen.dart';
import 'leaderboards_screen.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    String firstName = "User";

    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      firstName = user.displayName!.split(" ").first;
    }

    return AppBar(
      elevation: 0,
      toolbarHeight: 82,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,

      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),

      titleSpacing: 18,

      title: Row(
        children: [
          // ================= PROFILE =================
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MoreScreen()),
              );
            },

            child: Hero(
              tag: "profile",

              child: Container(
                padding: const EdgeInsets.all(2),

                decoration: BoxDecoration(
                  shape: BoxShape.circle,

                  gradient: LinearGradient(
                    colors: [
                      Colors.deepOrange.shade300,
                      Colors.orange.shade400,
                    ],
                  ),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withAlpha((0.25 * 255).round()),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),

                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white,

                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,

                  child: user?.photoURL == null
                      ? Icon(
                          Icons.person_rounded,
                          size: 24,
                          color: Colors.orange.shade700,
                        )
                      : null,
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          // ================= TEXT =================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,

              children: [
                Text(
                  "Welcome Back",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  "Hi, $firstName 👋",
                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // ================= ACTIONS =================
      actions: [
        _actionButton(
          icon: Icons.emoji_events_rounded,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
            );
          },
        ),

        const SizedBox(width: 16),
      ],
    );
  }

  // ================= ACTION BUTTON =================

  Widget _actionButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,

      child: Container(
        width: 44,
        height: 44,

        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),

        child: Icon(icon, color: Colors.black87, size: 24),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(82);
}
