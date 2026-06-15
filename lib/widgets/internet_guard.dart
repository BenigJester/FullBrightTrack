import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_navigator_service.dart';
import '../services/internet_status_service.dart';

class InternetGuard extends StatefulWidget {
  const InternetGuard({super.key, required this.child});

  final Widget child;

  @override
  State<InternetGuard> createState() => _InternetGuardState();
}

class _InternetGuardState extends State<InternetGuard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _dialogVisible = false;
  bool _checking = false;
  InternetStatus? _lastProblem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final status = await InternetStatusService.check();
      if (!mounted) return;
      if (status.isOk) {
        _lastProblem = null;
        return;
      }

      if (_lastProblem?.type == status.type && _dialogVisible) return;
      _lastProblem = status;
      await _showProblem(status);
    } finally {
      _checking = false;
    }
  }

  Future<void> _showProblem(InternetStatus status) async {
    if (_dialogVisible || !mounted) return;

    final navigatorContext = AppNavigatorService.context;
    if (navigatorContext == null || !navigatorContext.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showProblem(status));
      });
      return;
    }

    _dialogVisible = true;

    await showDialog<void>(
      context: navigatorContext,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFFF7F8FC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            icon: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                _iconFor(status.type),
                color: Colors.deepOrange,
                size: 30,
              ),
            ),
            title: Text(
              status.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Text(
              status.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final next = await InternetStatusService.check();
                    if (!context.mounted) return;
                    if (next.isOk) {
                      Navigator.of(context, rootNavigator: true).pop();
                      return;
                    }
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(next.message),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry connection'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: SystemNavigator.pop,
                  icon: const Icon(Icons.exit_to_app_rounded),
                  label: const Text('Exit app'),
                ),
              ),
            ],
          ),
        );
      },
    );

    _dialogVisible = false;
    unawaited(_check());
  }

  IconData _iconFor(InternetProblemType type) {
    return switch (type) {
      InternetProblemType.airplaneMode => Icons.airplanemode_active_rounded,
      InternetProblemType.wifiNoInternet => Icons.wifi_off_rounded,
      InternetProblemType.mobileDataOff => Icons.signal_cellular_off_rounded,
      _ => Icons.signal_wifi_connected_no_internet_4_rounded,
    };
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
