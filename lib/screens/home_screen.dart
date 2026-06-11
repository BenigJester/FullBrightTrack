import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/admin_alert_service.dart';
import '../services/auth_service.dart';
import '../services/device_readiness_service.dart';
import '../services/step_foreground_service.dart';
import 'home_tab.dart';
import 'steps_tab.dart';
import 'tasks_tab.dart';
import 'mood_tab.dart';
import 'streaks_tab.dart';
import 'appbar.dart';
import 'ai_analysis_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      const HomeTab(),
      const StepsTab(),
      const TasksTab(),
      const MoodTab(),
      const AiAnalysisScreen(),
      const StreakTab(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareSignedInDevice();
    });
  }

  Future<void> _prepareSignedInDevice() async {
    try {
      await DeviceReadinessService.registerAdminMessagingToken();
    } catch (error) {
      debugPrint('Admin FCM setup skipped: $error');
    }

    try {
      await AdminAlertService.startAdminAlertListener();
    } catch (error) {
      debugPrint('Admin alert listener skipped: $error');
    }

    final status = await DeviceReadinessService.checkStatus();
    if (!mounted) return;

    if (status.needsAttention) {
      await showDialog<void>(
        context: context,
        builder: (context) => _PermissionReadinessDialog(
          initialStatus: status,
          onChanged: () {
            if (mounted) setState(() {});
          },
        ),
      );
    }

    if (!mounted) return;
    await _ensureContactNumber();
  }

  Future<void> _ensureContactNumber() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      final monitoringDoc = await firestore
          .collection('admin_monitoring')
          .doc(user.uid)
          .get();

      final profilePhone =
          (userDoc.data()?['contactPhoneNumber'] as String?)?.trim() ?? '';
      final monitoringPhone =
          (monitoringDoc.data()?['contactPhoneNumber'] as String?)?.trim() ??
          '';

      if (_normalizePhilippineMobile(profilePhone) != null ||
          _normalizePhilippineMobile(monitoringPhone) != null) {
        return;
      }

      if (!mounted) return;
      final contact = await showDialog<_RequiredContactInfo>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _RequiredContactDialog(),
      );
      if (contact == null) return;

      await firestore.collection('users').doc(user.uid).set({
        'contactPhoneNumber': contact.phoneNumber,
        'contactRelationship': contact.relationship,
        'contactUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await firestore.collection('admin_monitoring').doc(user.uid).set({
        'contactPhoneNumber': contact.phoneNumber,
        'contactRelationship': contact.relationship,
        'contactUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Contact prompt skipped: $error');
    }
  }

  void onItemTapped(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  final auth = AuthService();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HomeAppBar(),
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: onItemTapped,
        type: BottomNavigationBarType.fixed,

        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_walk_outlined),
            activeIcon: Icon(Icons.directions_walk),
            label: "Steps",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            activeIcon: Icon(Icons.check_circle),
            label: "Tasks",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_emotions_outlined),
            activeIcon: Icon(Icons.emoji_emotions),
            label: "Mood",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: "AI",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_fire_department_outlined),
            activeIcon: Icon(Icons.local_fire_department),
            label: "Streaks",
          ),
        ],
      ),
    );
  }
}

const _contactRelationships = [
  'My number',
  'Mother',
  'Father',
  'Guardian',
  'Sibling',
  'Relative',
  'Trusted contact',
];

String? _normalizePhilippineMobile(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
  if (RegExp(r'^09\d{9}$').hasMatch(digits)) {
    return '+63${digits.substring(1)}';
  }
  if (RegExp(r'^\+639\d{9}$').hasMatch(digits)) return digits;
  if (RegExp(r'^639\d{9}$').hasMatch(digits)) return '+$digits';
  return null;
}

class _RequiredContactInfo {
  const _RequiredContactInfo({
    required this.phoneNumber,
    required this.relationship,
  });

  final String phoneNumber;
  final String relationship;
}

class _RequiredContactDialog extends StatefulWidget {
  const _RequiredContactDialog();

  @override
  State<_RequiredContactDialog> createState() => _RequiredContactDialogState();
}

class _RequiredContactDialogState extends State<_RequiredContactDialog> {
  final _phoneController = TextEditingController();
  String _relationship = _contactRelationships.first;
  String? _error;
  bool _expanded = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _save() {
    final phone = _normalizePhilippineMobile(_phoneController.text);
    if (phone == null) {
      setState(
        () => _error =
            'Enter a valid Philippine mobile number, like 09171234567.',
      );
      return;
    }

    Navigator.pop(
      context,
      _RequiredContactInfo(phoneNumber: phone, relationship: _relationship),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.phone_in_talk_rounded,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Add contact number',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A support contact is required so authorized staff can reach you or your trusted contact during verified safety reviews.',
                style: TextStyle(color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Philippine mobile number',
                  hintText: '09171234567',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.phone_android_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF7F8FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _expanded = !_expanded);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.family_restroom_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _relationship,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                        ],
                      ),
                      if (_expanded) ...[
                        const SizedBox(height: 10),
                        for (final relationship in _contactRelationships)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(relationship),
                            trailing: _relationship == relationship
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.deepOrange,
                                  )
                                : const Icon(
                                    Icons.radio_button_unchecked_rounded,
                                  ),
                            onTap: () {
                              setState(() {
                                _relationship = relationship;
                                _expanded = false;
                              });
                            },
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Save contact'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionReadinessDialog extends StatefulWidget {
  const _PermissionReadinessDialog({
    required this.initialStatus,
    required this.onChanged,
  });

  final DeviceReadinessStatus initialStatus;
  final VoidCallback onChanged;

  @override
  State<_PermissionReadinessDialog> createState() =>
      _PermissionReadinessDialogState();
}

class _PermissionReadinessDialogState extends State<_PermissionReadinessDialog>
    with WidgetsBindingObserver {
  late DeviceReadinessStatus status;
  DeviceReadinessAction? busyAction;

  @override
  void initState() {
    super.initState();
    status = widget.initialStatus;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshStatus(startService: true);
    }
  }

  Future<void> refreshStatus({bool startService = false}) async {
    final nextStatus = await DeviceReadinessService.checkStatus();
    if (!mounted) return;
    setState(() => status = nextStatus);
    widget.onChanged();

    if (startService) {
      await startStepServiceWhenReady();
    }
  }

  Future<void> startStepServiceWhenReady() async {
    final latest = await DeviceReadinessService.checkStatus();
    if (!latest.activityRecognitionGranted || !latest.notificationGranted) {
      return;
    }

    try {
      await StepForegroundService.start();
    } catch (error) {
      debugPrint('Could not start step foreground service: $error');
    }
  }

  Future<void> handleIssue(DeviceReadinessIssue issue) async {
    if (busyAction != null) return;

    setState(() => busyAction = issue.action);
    var allowed = false;

    try {
      switch (issue.action) {
        case DeviceReadinessAction.activity:
          allowed = await DeviceReadinessService.requestActivityRecognition();
        case DeviceReadinessAction.notification:
          allowed =
              await DeviceReadinessService.requestNotificationPermission();
        case DeviceReadinessAction.battery:
          allowed = await DeviceReadinessService.requestUnrestrictedBattery();
      }

      await refreshStatus(startService: true);

      if (!allowed &&
          mounted &&
          issue.action != DeviceReadinessAction.battery) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Android did not show the ${issue.title.toLowerCase()} popup. Please check app permissions in Settings.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => busyAction = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                      Icons.tune_rounded,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Setup needs attention',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'These permissions keep step tracking, reminders, and safety alerts reliable. Review each item below.',
                style: TextStyle(color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 16),
              for (final issue in status.issues) _issueTile(issue),
              if (!status.needsAttention)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'All important app access is allowed.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _issueTile(DeviceReadinessIssue issue) {
    final busy = busyAction == issue.action;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.18)),
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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.deepOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_issueIcon(issue), color: Colors.deepOrange, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  issue.description,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.3),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busyAction == null
                        ? () => handleIssue(issue)
                        : null,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                    label: Text(busy ? 'Checking...' : 'Allow'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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

  IconData _issueIcon(DeviceReadinessIssue issue) {
    return switch (issue.iconName) {
      'directions_walk' => Icons.directions_walk_rounded,
      'notifications' => Icons.notifications_active_outlined,
      'battery_alert' => Icons.battery_alert_rounded,
      _ => Icons.info_outline_rounded,
    };
  }
}
