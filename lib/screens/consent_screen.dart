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
          "Data Consent",
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
                    icon: Icons.psychology_alt_rounded,
                    title: "What FullBrightTrack analyzes",
                    text:
                        "With your permission, FullBrightTrack may process recent mood check-ins, mood intensity, step logs, journal entries, task titles, task status, deadlines, and locally detected warning labels to create AI wellness insights.",
                  ),
                  _section(
                    icon: Icons.admin_panel_settings_rounded,
                    title: "Why this matters",
                    text:
                        "The AI status and Admin Monitoring tools use these signals to estimate stress rank, confidence, and short rationale labels. These are review aids, not medical diagnoses.",
                  ),
                  _section(
                    icon: Icons.security_rounded,
                    title: "How your data is handled",
                    text:
                        "Raw data is sent only to the configured AI backend when this consent is active. Admin Monitoring stores derived values such as score, rank, confidence, rationale, and warning metadata instead of copying full raw journal text.",
                  ),
                  _section(
                    icon: Icons.notifications_active_rounded,
                    title: "Safety alerts",
                    text:
                        "If a critical warning signal is detected, the app can create a privacy-safe admin alert. The alert includes review metadata and does not include full journal text.",
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
                label: const Text("I understand and agree"),
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
            "AI wellness data consent",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Please review how FullBrightTrack uses raw wellness data before continuing.",
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
