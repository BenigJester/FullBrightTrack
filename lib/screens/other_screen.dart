import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/admin_access_service.dart';
import '../services/admin_alert_service.dart';
import '../services/auth_service.dart';
import '../services/backend_account_service.dart';
import '../services/device_readiness_service.dart';
import '../services/display_name_service.dart';
import '../services/logout_service.dart';
import '../services/notification_service.dart';
import '../services/notification_history_service.dart';
import '../services/reminder_scheduler_service.dart';
import '../services/step_foreground_service.dart';
import 'admin_monitoring_screen.dart';

String _firstName(String? name) {
  return DisplayNameService.firstName(name);
}

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() => _loggingOut = true);

    try {
      await LogoutService.logout();

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).popUntil((route) {
        return route.isFirst;
      });
    } catch (e) {
      debugPrint("Logout error: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text("Could not log out. Please try again."),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  Future<void> _refreshProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    await user?.reload();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final firstName = _firstName(user?.displayName);

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

      body: Stack(
        children: [
          IgnorePointer(
            ignoring: _loggingOut,
            child: RefreshIndicator(
              color: Colors.deepOrange,
              onRefresh: _refreshProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                            firstName,
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
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AccountInformationScreen(),
                          ),
                        );
                        await _refreshProfile();
                      },
                    ),

                    _tile(
                      icon: Icons.notifications_none_rounded,
                      title: "Step Reminders",
                      subtitle: "Manage step reminder notifications",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationSettingsScreen(),
                          ),
                        );
                      },
                    ),

                    FutureBuilder<bool>(
                      future: AdminAccessService.isCurrentUserAdmin(),
                      builder: (context, snapshot) {
                        if (snapshot.data != true) {
                          return const SizedBox.shrink();
                        }

                        return _tile(
                          icon: Icons.history_rounded,
                          title: "Notification History",
                          subtitle: "View and clear admin safety alerts",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const NotificationHistoryScreen(),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    _tile(
                      icon: Icons.verified_user_outlined,
                      title: "Permissions",
                      subtitle:
                          "Review steps, notifications, and battery access",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PermissionManagerScreen(),
                          ),
                        );
                      },
                    ),

                    FutureBuilder<bool>(
                      future: AdminAccessService.isCurrentUserAdmin(),
                      builder: (context, snapshot) {
                        if (snapshot.data != true) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          children: [
                            _tile(
                              icon: Icons.admin_panel_settings_rounded,
                              title: "Admin Monitoring",
                              subtitle:
                                  "Review wellness signals and stress ranks",
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AdminMonitoringScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),

                    _tile(
                      icon: Icons.info_outline_rounded,
                      title: "About",
                      subtitle: "Application information",
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: "Productivity and Wellbeing",
                          applicationVersion: "0.4.0-alpha+5",
                        );
                      },
                    ),

                    _tile(
                      icon: Icons.logout_rounded,
                      title: _loggingOut ? "Logging out..." : "Logout",
                      subtitle: _loggingOut
                          ? "Saving your latest steps before signing out"
                          : "Sign out from your account",
                      isLogout: true,
                      trailing: _loggingOut
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : null,
                      onTap: _logout,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_loggingOut)
            Container(
              color: Colors.black.withValues(alpha: 0.12),
              child: const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.deepOrange),
                        SizedBox(height: 14),
                        Text(
                          "Logging out...",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    Widget? trailing,
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

                trailing ??
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

class AccountInformationScreen extends StatefulWidget {
  const AccountInformationScreen({super.key});

  @override
  State<AccountInformationScreen> createState() =>
      _AccountInformationScreenState();
}

class _AccountInformationScreenState extends State<AccountInformationScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    _nameController.text = _firstName(user?.displayName);
    _emailController.text = user?.email ?? "";
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = DisplayNameService.normalize(_nameController.text);
    final error = DisplayNameService.validationError(name);

    if (error != null) {
      _showMessage(error);
      return;
    }

    _nameController.text = name;
    setState(() => _saving = true);

    try {
      await user.updateDisplayName(name);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': user.email,
        'photoUrl': user.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await user.reload();

      if (!mounted) return;
      _showMessage("Account information updated");
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showMessage("Could not update account information");
      debugPrint("Profile update error: $e");
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addPasswordSignIn() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;

    if (email == null || email.isEmpty) {
      _showMessage("No email address is linked to this account");
      return;
    }

    final confirmed = await _showAccountActionDialog(
      title: "Add password sign-in?",
      message:
          "This lets you sign in with either Google or email and password using $email.",
      confirmLabel: "Add password",
      icon: Icons.add_moderator_outlined,
    );
    if (!confirmed) return;

    final password = await _showPasswordDialog();
    if (password == null) return;

    setState(() => _saving = true);

    try {
      await AuthService().linkPasswordToCurrentUser(email, password);
      await user!.reload();

      if (!mounted) return;
      _showMessage("Password sign-in added");
      setState(() {});
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'provider-already-linked') {
        _showMessage("Password sign-in is already enabled");
      } else if (e.code == 'requires-recent-login') {
        _showMessage("Please log out, sign in with Google again, then retry");
      } else if (e.code == 'weak-password') {
        _showMessage("Password must be at least 6 characters");
      } else {
        _showMessage(e.message ?? "Could not add password sign-in");
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage("Could not add password sign-in");
      debugPrint("Add password sign-in error: $e");
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _requestPasswordReset() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;

    if (email == null || email.isEmpty) {
      _showMessage("No email address is linked to this account");
      return;
    }

    final confirmed = await _showAccountActionDialog(
      title: "Send password reset?",
      message: "A secure password reset link will be sent to $email.",
      confirmLabel: "Send reset link",
      icon: Icons.lock_reset_rounded,
    );
    if (!confirmed) return;

    setState(() => _saving = true);

    try {
      final result = await BackendAccountService.requestPasswordReset(
        email: email,
      );

      if (!mounted) return;
      _showMessage(
        result.requestId.isEmpty
            ? "If this email exists, a password reset link will be sent"
            : "Password reset link sent. Check your email",
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage("Could not send password reset link");
      debugPrint("Password reset request error: $e");
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _linkGoogleSignIn() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;

    if (email == null || email.isEmpty) {
      _showMessage("No email address is linked to this account");
      return;
    }

    final confirmed = await _showAccountActionDialog(
      title: "Verify with Google Sign-In?",
      message:
          "Choose the Google account for $email. After verification, this account can also use Google Sign-In.",
      confirmLabel: "Verify with Google",
      icon: Icons.g_mobiledata_rounded,
    );
    if (!confirmed) return;

    setState(() => _saving = true);

    try {
      await AuthService().linkGoogleToCurrentUser();
      await user!.reload();

      if (!mounted) return;
      _showMessage("Google Sign-In verified for this account");
      setState(() {});
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'provider-already-linked') {
        _showMessage("Google Sign-In is already verified");
      } else if (e.code == 'credential-already-in-use') {
        _showMessage("That Google account is already linked elsewhere");
      } else if (e.code == 'requires-recent-login') {
        _showMessage("Please log out, sign in again, then retry");
      } else {
        _showMessage(e.message ?? "Could not verify Google Sign-In");
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage("Could not verify Google Sign-In");
      debugPrint("Google link error: $e");
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _showAccountActionDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
            child: Icon(icon, color: Colors.deepOrange, size: 30),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.45),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(confirmLabel),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<String?> _showPasswordDialog() async {
    _passwordController.clear();
    _confirmPasswordController.clear();
    _obscurePassword = true;
    _obscureConfirmPassword = true;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF7F8FC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.add_moderator_outlined,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Add Password",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: _settingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Create a password so this Google account can also sign in with email.",
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 16),
                _input(
                  controller: _passwordController,
                  label: "Password",
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? "Show password"
                        : "Hide password",
                    onPressed: () => setDialogState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _input(
                  controller: _confirmPasswordController,
                  label: "Confirm password",
                  icon: Icons.lock_person_outlined,
                  obscureText: _obscureConfirmPassword,
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirmPassword
                        ? "Show password"
                        : "Hide password",
                    onPressed: () => setDialogState(
                      () => _obscureConfirmPassword =
                          !_obscureConfirmPassword,
                    ),
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
              label: const Text("Cancel"),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                final password = _passwordController.text.trim();
                final confirm = _confirmPasswordController.text.trim();

                if (password.length < 6) {
                  _showMessage("Password must be at least 6 characters");
                  return;
                }

                if (password != confirm) {
                  _showMessage("Passwords do not match");
                  return;
                }

                Navigator.pop(context, password);
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text("Add"),
            ),
          ],
        );
          },
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final provider = user?.providerData.isNotEmpty == true
        ? user!.providerData.first.providerId
        : "password";
    final providers =
        user?.providerData.map((info) => info.providerId).toSet() ?? {};
    final hasPassword = providers.contains('password');
    final hasGoogle = providers.contains('google.com');

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: _settingsAppBar("Account Information"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _settingsCard(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? const Icon(Icons.person, size: 42)
                        : null,
                  ),
                  const SizedBox(height: 18),
                  _input(
                    controller: _nameController,
                    label: "Display name",
                    icon: Icons.badge_outlined,
                    helperText: "3-${DisplayNameService.maxLength} characters",
                    maxLength: DisplayNameService.maxLength,
                  ),
                  const SizedBox(height: 14),
                  _input(
                    controller: _emailController,
                    label: "Email",
                    icon: Icons.email_outlined,
                    enabled: false,
                  ),
                  const SizedBox(height: 14),
                  _accountSummaryCard(
                    provider: provider,
                    providers: providers,
                    email: user?.email ?? '',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _primaryButton(
              label: _saving ? "Saving..." : "Save Changes",
              icon: Icons.save_rounded,
              onPressed: _saving ? null : _saveProfile,
            ),
            if (!hasPassword && hasGoogle) ...[
              const SizedBox(height: 12),
              _secondaryButton(
                label: "Add Password",
                icon: Icons.add_moderator_outlined,
                onPressed: _saving ? null : _addPasswordSignIn,
              ),
            ] else if (hasPassword && !hasGoogle) ...[
              const SizedBox(height: 12),
              _secondaryButton(
                label: "Verify with Google Sign-In",
                icon: Icons.g_mobiledata_rounded,
                onPressed: _saving ? null : _linkGoogleSignIn,
              ),
              const SizedBox(height: 12),
              _secondaryButton(
                label: "Reset Password",
                icon: Icons.lock_reset_rounded,
                onPressed: _saving ? null : _requestPasswordReset,
              ),
            ] else if (hasPassword) ...[
              const SizedBox(height: 12),
              _secondaryButton(
                label: "Reset Password",
                icon: Icons.lock_reset_rounded,
                onPressed: _saving ? null : _requestPasswordReset,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _accountSummaryCard({
    required String provider,
    required Set<String> providers,
    required String email,
  }) {
    final label = provider == 'google.com'
        ? 'Google'
        : provider == 'password'
        ? 'Email and password'
        : provider;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Account status",
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _summaryRow("Email", email.isEmpty ? "Not available" : email),
          const SizedBox(height: 10),
          _summaryRow("Primary sign-in", label),
          const SizedBox(height: 10),
          _summaryRow(
            "Linked methods",
            providers.isEmpty
                ? label
                : providers
                      .map(
                        (value) => value == 'google.com'
                            ? 'Google'
                            : value == 'password'
                            ? 'Password'
                            : value,
                      )
                      .join(', '),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _enabled = true;
  int _intervalHours = 2;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _enabled = prefs.getBool(ReminderSchedulerService.enabledKey) ?? true;
      _intervalHours = prefs.getInt(ReminderSchedulerService.intervalKey) ?? 2;
      _loading = false;
    });
  }

  Future<void> _saveSettings({bool? enabled, int? intervalHours}) async {
    setState(() => _saving = true);

    final nextEnabled = enabled ?? _enabled;
    final nextInterval = intervalHours ?? _intervalHours;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ReminderSchedulerService.enabledKey, nextEnabled);
      await prefs.setInt(ReminderSchedulerService.intervalKey, nextInterval);

      if (nextEnabled) {
        await _requestNotificationPermission();
      }

      await ReminderSchedulerService.schedule(
        enabled: nextEnabled,
        intervalHours: nextInterval,
      );

      if (!mounted) return;

      setState(() {
        _enabled = nextEnabled;
        _intervalHours = nextInterval;
      });

      _showMessage("Notification settings updated");
    } catch (e) {
      if (!mounted) return;
      _showMessage("Could not update notification settings");
      debugPrint("Notification settings error: $e");
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    await DeviceReadinessService.requestNotificationPermission();
  }

  Future<void> _sendTestNotification() async {
    await _requestNotificationPermission();

    final prefs = await SharedPreferences.getInstance();
    final steps = prefs.getInt('bg_steps') ?? 0;

    const androidDetails = AndroidNotificationDetails(
      'hourly_steps',
      'Hourly Step Reminder',
      channelDescription: 'Hourly wellness reminders',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      onlyAlertOnce: true,
    );

    await NotificationService.notifications.show(
      id: 101,
      title: 'Step Reminder',
      body: '$steps steps today',
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),
        appBar: _settingsAppBar("Notifications"),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: _settingsAppBar("Notifications"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _settingsCard(
              child: Column(
                children: [
                  SwitchListTile(
                    value: _enabled,
                    onChanged: _saving
                        ? null
                        : (value) => _saveSettings(enabled: value),
                    activeThumbColor: Colors.deepOrange,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "Step reminders",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      "Show a reminder notification while step tracking is active",
                    ),
                  ),
                  const Divider(height: 28),
                  _intervalOption(1, "Every hour"),
                  _intervalOption(2, "Every 2 hours"),
                  _intervalOption(3, "Every 3 hours"),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _secondaryButton(
              label: "Send Test Notification",
              icon: Icons.notifications_active_outlined,
              onPressed: _sendTestNotification,
            ),
          ],
        ),
      ),
    );
  }

  Widget _intervalOption(int hours, String label) {
    final selected = _intervalHours == hours;
    final disabled = !_enabled || _saving;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: disabled ? null : () => _saveSettings(intervalHours: hours),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: disabled
                  ? Colors.grey.shade400
                  : selected
                  ? Colors.deepOrange
                  : Colors.grey.shade500,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: disabled ? Colors.grey.shade500 : Colors.black87,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  late Future<List<NotificationHistoryItem>> _historyFuture;
  late Future<bool> _adminFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _adminFuture = AdminAccessService.isCurrentUserAdmin();
    _historyFuture = NotificationHistoryService.load();
  }

  Future<void> _refresh() async {
    setState(() {
      _historyFuture = NotificationHistoryService.load();
    });

    await _historyFuture;
  }

  Future<void> _delete(String id) async {
    if (_busy) return;

    setState(() => _busy = true);
    await NotificationHistoryService.delete(id);
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clearAll() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text("Clear notification history?"),
          content: const Text(
            "This removes saved alert history from this device only.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Clear all"),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    await NotificationHistoryService.clearAll();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          "Notification History",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: "Clear all",
            onPressed: _busy ? null : _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<bool>(
        future: _adminFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data != true) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "Notification history is available for admins only.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
              ),
            );
          }

          return FutureBuilder<List<NotificationHistoryItem>>(
            future: _historyFuture,
            builder: (context, historySnapshot) {
              if (historySnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final items =
                  historySnapshot.data ?? const <NotificationHistoryItem>[];

              return RefreshIndicator(
                color: Colors.deepOrange,
                onRefresh: _refresh,
                child: items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 120),
                          Icon(
                            Icons.notifications_off_outlined,
                            color: Colors.grey.shade500,
                            size: 54,
                          ),
                          const SizedBox(height: 12),
                          const Center(
                            child: Text(
                              "No admin alerts yet",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Critical warning alerts will appear here after they are received on this admin account.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _NotificationHistoryTile(
                            item: item,
                            busy: _busy,
                            onDelete: () => _delete(item.id),
                            onReview: item.userId == null
                                ? null
                                : () => AdminAlertService.openAdminMonitoring(
                                    userId: item.userId,
                                  ),
                          );
                        },
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemCount: items.length,
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationHistoryTile extends StatelessWidget {
  const _NotificationHistoryTile({
    required this.item,
    required this.busy,
    required this.onDelete,
    required this.onReview,
  });

  final NotificationHistoryItem item;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onReview,
      child: _settingsCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatHistoryTime(item.createdAt),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: "Delete",
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }

  String _formatHistoryTime(DateTime value) {
    final hour = value.hour > 12
        ? value.hour - 12
        : value.hour == 0
        ? 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} $hour:$minute $period';
  }
}

class PermissionManagerScreen extends StatefulWidget {
  const PermissionManagerScreen({super.key});

  @override
  State<PermissionManagerScreen> createState() =>
      _PermissionManagerScreenState();
}

class _PermissionManagerScreenState extends State<PermissionManagerScreen>
    with WidgetsBindingObserver {
  late Future<DeviceReadinessStatus> _statusFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusFuture = DeviceReadinessService.checkStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(startService: true);
    }
  }

  Future<void> _refresh({bool startService = false}) async {
    setState(() {
      _statusFuture = DeviceReadinessService.checkStatus();
    });

    final status = await _statusFuture;
    if (startService) {
      await _startStepServiceWhenReady(status);
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await action();
      await _refresh(startService: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startStepServiceWhenReady(DeviceReadinessStatus status) async {
    if (!status.activityRecognitionGranted || !status.notificationGranted) {
      return;
    }

    try {
      await StepForegroundService.start();
    } catch (error) {
      debugPrint('Could not start step foreground service: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: _settingsAppBar("Permissions"),
      body: FutureBuilder<DeviceReadinessStatus>(
        future: _statusFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final status =
              snapshot.data ??
              const DeviceReadinessStatus(
                activityRecognitionGranted: false,
                notificationGranted: false,
                unrestrictedBattery: true,
              );

          return RefreshIndicator(
            color: Colors.deepOrange,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                _settingsCard(
                  child: Column(
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
                              Icons.verified_user_outlined,
                              color: Colors.deepOrange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "App permission manager",
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
                        "These settings help FullBrightTrack keep step tracking, reminders, and safety alerts reliable.",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _PermissionAccessTile(
                  icon: Icons.directions_walk_rounded,
                  title: "Physical Activity",
                  description:
                      "Allows daily step tracking and wellness summaries.",
                  statusLabel: status.activityRecognitionGranted
                      ? "Allowed"
                      : "Not allowed",
                  allowed: status.activityRecognitionGranted,
                  buttonLabel: "Allow steps",
                  manageLabel: "Manage / disable",
                  busy: _busy,
                  onPressed: () => _runAction(() async {
                    await DeviceReadinessService.requestActivityRecognition();
                  }),
                  onManagePressed: () => _runAction(() async {
                    await DeviceReadinessService.openPermissionSettings();
                  }),
                ),
                _PermissionAccessTile(
                  icon: Icons.notifications_active_outlined,
                  title: "Notifications",
                  description:
                      "Allows reminders and admin safety alerts to appear.",
                  statusLabel: status.notificationGranted
                      ? "Allowed"
                      : "Not allowed",
                  allowed: status.notificationGranted,
                  buttonLabel: "Allow alerts",
                  manageLabel: "Manage / disable",
                  busy: _busy,
                  onPressed: () => _runAction(() async {
                    await DeviceReadinessService.requestNotificationPermission();
                  }),
                  onManagePressed: () => _runAction(() async {
                    await DeviceReadinessService.openPermissionSettings();
                  }),
                ),
                _PermissionAccessTile(
                  icon: Icons.battery_charging_full_rounded,
                  title: "Battery usage",
                  description:
                      "Android may show Restricted, Optimized, or Unrestricted. Choose Unrestricted for best boot and background tracking.",
                  statusLabel: status.unrestrictedBattery
                      ? "Unrestricted"
                      : "Optimized / Restricted",
                  allowed: status.unrestrictedBattery,
                  buttonLabel: "Set unrestricted",
                  manageLabel: "Choose battery mode",
                  busy: _busy,
                  onPressed: () => _runAction(
                    DeviceReadinessService.requestUnrestrictedBattery,
                  ),
                  onManagePressed: () => _runAction(
                    DeviceReadinessService.openBatteryOptimizationSettings,
                  ),
                ),
                const SizedBox(height: 4),
                _secondaryButton(
                  label: "Refresh Status",
                  icon: Icons.refresh_rounded,
                  onPressed: _busy ? () {} : _refresh,
                ),
                const SizedBox(height: 12),
                Text(
                  "Tip: On some Android phones, choose Battery > Unrestricted or Don't optimize for FullBrightTrack.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, height: 1.4),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PermissionAccessTile extends StatelessWidget {
  const _PermissionAccessTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.statusLabel,
    required this.allowed,
    required this.buttonLabel,
    required this.manageLabel,
    required this.busy,
    required this.onPressed,
    required this.onManagePressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String statusLabel;
  final bool allowed;
  final String buttonLabel;
  final String manageLabel;
  final bool busy;
  final VoidCallback onPressed;
  final VoidCallback onManagePressed;

  @override
  Widget build(BuildContext context) {
    final color = allowed ? Colors.green : Colors.deepOrange;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _settingsCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _PermissionStatusBadge(
                        allowed: allowed,
                        label: statusLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!allowed)
                        FilledButton.icon(
                          onPressed: busy ? null : onPressed,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.touch_app_rounded),
                          label: Text(buttonLabel),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            "Ready",
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: busy ? null : onManagePressed,
                        icon: const Icon(Icons.tune_rounded),
                        label: Text(manageLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionStatusBadge extends StatelessWidget {
  const _PermissionStatusBadge({required this.allowed, required this.label});

  final bool allowed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = allowed ? Colors.green : Colors.orange.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

PreferredSizeWidget _settingsAppBar(String title) {
  return AppBar(
    elevation: 0,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    title: Text(
      title,
      style: const TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

Widget _settingsCard({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

Widget _input({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  bool enabled = true,
  bool obscureText = false,
  String? helperText,
  int? maxLength,
  Widget? suffixIcon,
}) {
  return TextField(
    controller: controller,
    enabled: enabled,
    obscureText: obscureText,
    inputFormatters: maxLength == null
        ? null
        : [LengthLimitingTextInputFormatter(maxLength)],
    decoration: InputDecoration(
      labelText: label,
      helperText: helperText,
      counterText: maxLength == null ? null : '',
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: enabled ? const Color(0xFFF7F8FC) : const Color(0xFFEDEFF5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

Widget _primaryButton({
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
}) {
  return ElevatedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.deepOrange,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

Widget _secondaryButton({
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.deepOrange,
      minimumSize: const Size.fromHeight(54),
      side: BorderSide(color: Colors.deepOrange.withValues(alpha: 0.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
