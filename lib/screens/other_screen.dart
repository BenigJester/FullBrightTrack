import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          "More",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            // ================= PROFILE CARD =================
            Container(
              padding: const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),

              child: Column(
                children: [
                  Hero(
                    tag: "profile",

                    child: CircleAvatar(
                      radius: 42,
                      backgroundImage: user?.photoURL != null
                          ? NetworkImage(user!.photoURL!)
                          : null,

                      child: user?.photoURL == null
                          ? const Icon(Icons.person, size: 42)
                          : null,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    user?.displayName ?? "Guest User",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    user?.email ?? "",
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ================= MENU =================
            _tile(
              icon: Icons.person_outline_rounded,
              title: "Account Information",
              subtitle: "Manage your account details",
              onTap: () {},
            ),

            _tile(
              icon: Icons.notifications_none_rounded,
              title: "Notifications",
              subtitle: "Manage reminders and alerts",
              onTap: () {},
            ),

            _tile(
              icon: Icons.info_outline_rounded,
              title: "About",
              subtitle: "Application information",
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: "Wellness App",
                  applicationVersion: "1.0.0",
                );
              },
            ),

            _tile(
              icon: Icons.logout_rounded,
              title: "Logout",
              subtitle: "Sign out from your account",
              isLogout: true,
              onTap: () async {
                await FirebaseAuth.instance.signOut();

                if (!context.mounted) return;

                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ================= TILE =================

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLogout = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),

      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),

        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,

          child: Container(
            padding: const EdgeInsets.all(18),

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),

              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),

            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,

                  decoration: BoxDecoration(
                    color: isLogout
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),

                    borderRadius: BorderRadius.circular(16),
                  ),

                  child: Icon(
                    icon,
                    color: isLogout ? Colors.red : Colors.orange,
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isLogout ? Colors.red : Colors.black87,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
