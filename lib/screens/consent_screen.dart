import 'package:flutter/material.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final _scrollController = ScrollController();
  bool _canAgree = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _canAgree) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 24) {
      setState(() => _canAgree = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          "Privacy Policy",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  _section(
                    icon: Icons.person_pin_circle_rounded,
                    title: "Information the app may use",
                    text:
                        "FullBrightTrack may use account details, profile information, contact information, mood check-ins, mood intensity, step logs, journal entries, task titles, task status, deadlines, and warning labels to provide the app experience.",
                  ),
                  _section(
                    icon: Icons.psychology_alt_rounded,
                    title: "AI wellness analysis",
                    text:
                        "When enabled, the app may send relevant wellness data to the configured AI backend to produce stress level, confidence, mood suggestions, task guidance, step insights, and support recommendations. These outputs are support tools only, not medical diagnosis or emergency care.",
                  ),
                  _section(
                    icon: Icons.security_rounded,
                    title: "Privacy and storage",
                    text:
                        "Data is stored in Firebase services used by the app and may be processed by the configured backend. Access is limited by account role and security rules. Admin screens are intended for authorized review and support only.",
                  ),
                  _section(
                    icon: Icons.notifications_active_rounded,
                    title: "Safety alerts and admin review",
                    text:
                        "If the system detects possible harmful, explicit, or high-risk language, it may create an admin alert so authorized staff can review the signal, verify it, mark it resolved, or mark it as a false positive.",
                  ),
                  _section(
                    icon: Icons.manage_accounts_rounded,
                    title: "Your control",
                    text:
                        "You are responsible for keeping account information accurate, including contact details when required. App records may be updated when you change mood, journal, task, step, profile, or support information.",
                  ),
                  _section(
                    icon: Icons.info_outline_rounded,
                    title: "Important acknowledgement",
                    text:
                        "By continuing, you acknowledge that you have read this privacy policy summary and understand that FullBrightTrack is a wellness and productivity support app. For urgent mental health or safety concerns, contact trusted support or local emergency services.",
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.deepOrange.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Text(
                      "Scroll to the end to enable the agreement button.",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _canAgree
                    ? () => Navigator.pop(context, true)
                    : null,
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text("I acknowledge the Privacy Policy"),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8A00), Color(0xFFE65100)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, color: Colors.white, size: 38),
          SizedBox(height: 12),
          Text(
            "Privacy Policy acknowledgement",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Please review how FullBrightTrack handles wellness, account, and support data before continuing.",
            style: TextStyle(color: Colors.white, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
