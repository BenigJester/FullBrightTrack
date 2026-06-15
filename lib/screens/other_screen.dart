import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../services/admin_access_service.dart';
import '../services/auth_service.dart';
import '../services/backend_account_service.dart';
import '../services/device_readiness_service.dart';
import '../services/display_name_service.dart';
import '../services/logout_service.dart';
import '../services/notification_history_service.dart';
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
                          applicationVersion: "1.0.8",
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
  static const _contactRelationships = [
    'Student',
    'Mother',
    'Father',
    'Guardian',
    'Sibling',
    'Relative',
    'Other',
  ];

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String _contactRelationship = _contactRelationships.first;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _contactExpanded = false;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    _nameController.text = _firstName(user?.displayName);
    _emailController.text = user?.email ?? "";
    _loadContactInformation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadContactInformation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final monitoringDoc = await FirebaseFirestore.instance
          .collection('admin_monitoring')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? const <String, dynamic>{};
      final monitoringData = monitoringDoc.data() ?? const <String, dynamic>{};
      final phone =
          (userData['contactPhoneNumber'] as String?)?.trim().isNotEmpty == true
          ? (userData['contactPhoneNumber'] as String).trim()
          : (monitoringData['contactPhoneNumber'] as String?)?.trim() ?? '';
      final relationship =
          (userData['contactRelationship'] as String?)?.trim().isNotEmpty ==
              true
          ? (userData['contactRelationship'] as String).trim()
          : (monitoringData['contactRelationship'] as String?)?.trim() ?? '';

      if (!mounted) return;
      setState(() {
        _phoneController.text = phone;
        if (_contactRelationships.contains(relationship)) {
          _contactRelationship = relationship;
        }
      });
    } catch (error) {
      debugPrint('Contact information load error: $error');
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = DisplayNameService.normalize(_nameController.text);
    final error = DisplayNameService.validationError(name);
    final phoneInput = _phoneController.text.trim();
    final normalizedPhone = phoneInput.isEmpty
        ? ''
        : _normalizePhilippineMobile(phoneInput);

    if (error != null) {
      _showMessage(error);
      return;
    }

    if (phoneInput.isNotEmpty && normalizedPhone == null) {
      _showMessage("Enter a valid Philippine mobile number");
      return;
    }

    _nameController.text = name;
    _phoneController.text = normalizedPhone ?? '';
    setState(() => _saving = true);

    try {
      await user.updateDisplayName(name);
      final contactData = {
        'contactPhoneNumber': normalizedPhone ?? '',
        'contactRelationship':
            normalizedPhone == null || normalizedPhone.isEmpty
            ? ''
            : _contactRelationship,
        'contactUpdatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': user.email,
        'photoUrl': user.photoURL,
        ...contactData,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance
          .collection('admin_monitoring')
          .doc(user.uid)
          .set({
            'email': user.email,
            ...contactData,
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
            ? "Password reset request completed"
            : "Password reset link sent. Check your email within 5 minutes",
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
    _obscurePassword = true;

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
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
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

                    if (password.length < 6) {
                      _showMessage("Password must be at least 6 characters");
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
                  _input(
                    controller: _phoneController,
                    label: "Contact number",
                    icon: Icons.phone_rounded,
                    helperText:
                        "Philippine mobile: 09XXXXXXXXX or +639XXXXXXXXX",
                    maxLength: 16,
                  ),
                  const SizedBox(height: 14),
                  _contactRelationshipCard(),
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

  Widget _contactRelationshipCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: ExpansionTile(
        initiallyExpanded: _contactExpanded,
        onExpansionChanged: (value) => setState(() => _contactExpanded = value),
        leading: const Icon(
          Icons.family_restroom_rounded,
          color: Colors.deepOrange,
        ),
        title: const Text(
          "Contact relationship",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(_contactRelationship),
        children: [
          for (final relationship in _contactRelationships)
            ListTile(
              onTap: _saving
                  ? null
                  : () => setState(() => _contactRelationship = relationship),
              title: Text(relationship),
              trailing: _contactRelationship == relationship
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.deepOrange,
                    )
                  : const Icon(Icons.circle_outlined),
            ),
        ],
      ),
    );
  }
}

String? _normalizePhilippineMobile(String? raw) {
  final cleaned = (raw ?? '').replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (RegExp(r'^09\d{9}$').hasMatch(cleaned)) {
    return '+63${cleaned.substring(1)}';
  }
  if (RegExp(r'^\+639\d{9}$').hasMatch(cleaned)) {
    return cleaned;
  }
  if (RegExp(r'^639\d{9}$').hasMatch(cleaned)) {
    return '+$cleaned';
  }
  return null;
}

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  late Future<List<NotificationHistoryItem>> _historyFuture;
  final Set<String> _deletingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _historyFuture = NotificationHistoryService.load();
  }

  Future<void> _refresh() async {
    setState(() {
      _historyFuture = NotificationHistoryService.load();
    });
    await _historyFuture;
  }

  Future<void> _delete(String id) async {
    if (_deletingIds.contains(id)) return;
    setState(() => _deletingIds.add(id));
    try {
      await NotificationHistoryService.delete(id);
      await _refresh();
    } finally {
      if (mounted) setState(() => _deletingIds.remove(id));
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear notification history?"),
        content: const Text(
          "This removes saved admin notification history from this device account.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text("Clear"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await NotificationHistoryService.clearAll();
    await _refresh();
  }

  void _openItem(NotificationHistoryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminMonitoringScreen(
          initialUserId: item.userId == null || item.userId!.isEmpty
              ? null
              : item.userId,
          refreshOnOpen: true,
        ),
      ),
    );
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
            tooltip: "Clear history",
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<NotificationHistoryItem>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "Could not load notification history.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            );
          }

          final items = snapshot.data ?? const <NotificationHistoryItem>[];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "No admin notifications yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: Colors.deepOrange,
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final deleting = _deletingIds.contains(item.id);
                return _settingsCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.notifications_active_outlined,
                        color: Colors.deepOrange,
                      ),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      item.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openItem(item),
                    trailing: deleting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: "Delete",
                            onPressed: () => _delete(item.id),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
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
