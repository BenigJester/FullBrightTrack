import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/app_check_service.dart';
import '../services/auth_service.dart';
import '../services/backend_account_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AppCheckService.activate();
  runApp(const FullBrightDeveloperConsoleApp());
}

class FullBrightDeveloperConsoleApp extends StatelessWidget {
  const FullBrightDeveloperConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FullBrightTrack Developer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const DeveloperConsoleScreen(),
    );
  }
}

class DeveloperConsoleScreen extends StatefulWidget {
  const DeveloperConsoleScreen({super.key});

  @override
  State<DeveloperConsoleScreen> createState() => _DeveloperConsoleScreenState();
}

class _DeveloperConsoleScreenState extends State<DeveloperConsoleScreen> {
  static const int _usersPerPage = 20;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _userSearchController = TextEditingController();
  final _userPageController = TextEditingController(text: '1');
  final _userSearchFocusNode = FocusNode();

  String? _message;
  bool _authBusy = false;
  bool _obscurePassword = true;
  String? _busyUserId;
  int _currentUserPage = 1;
  String _appliedUserSearch = '';
  String? _developerAccessUid;
  Future<bool>? _developerAccessFuture;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _userSearchController.dispose();
    _userPageController.dispose();
    _userSearchFocusNode.dispose();
    super.dispose();
  }

  String get _backendBaseUrl {
    const configured = String.fromEnvironment('FULLBRIGHT_BACKEND_URL');
    final configuredUrl = _validBackendBaseUrl(configured);
    if (configuredUrl != null) {
      return configuredUrl;
    }

    const stressUrl = String.fromEnvironment('GENKIT_STRESS_FLOW_URL');
    final stressUri = Uri.tryParse(stressUrl.trim());
    if (stressUri != null && stressUri.hasScheme && stressUri.host.isNotEmpty) {
      final segments = stressUri.pathSegments.where((part) => part != 'stress');
      final baseUrl = stressUri
          .replace(pathSegments: segments, query: '', fragment: '')
          .toString();
      final normalized = _validBackendBaseUrl(baseUrl);
      if (normalized != null) return normalized;
    }

    const localUrl = String.fromEnvironment(
      'FULLBRIGHT_BACKEND_LOCAL_URL',
      defaultValue: 'http://10.0.2.2:8080',
    );
    return _validBackendBaseUrl(localUrl) ?? 'http://10.0.2.2:8080';
  }

  String? _validBackendBaseUrl(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return trimmed;
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = 'Enter admin email and password.');
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Sign in to developer tools?',
      message:
          'This opens developer-only user and credential management for $email.',
      confirmLabel: 'Sign in',
      icon: Icons.login_rounded,
    );
    if (!confirmed) return;

    setState(() => _authBusy = true);
    try {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final allowed = await _waitForDeveloperAccess();
      if (!allowed) {
        setState(
          () => _message =
              'Signed in, but this account is not currently marked role: developer.',
        );
        return;
      }
      setState(() => _message = 'Signed in. Developer rules still apply.');
    } catch (error) {
      setState(() => _message = 'Sign-in failed: $error');
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final confirmed = await _confirmAction(
      title: 'Continue with Google?',
      message: 'Choose a Google account that has role: developer in Firestore.',
      confirmLabel: 'Continue',
      icon: Icons.g_mobiledata_rounded,
    );
    if (!confirmed) return;

    setState(() => _authBusy = true);
    try {
      await FirebaseAuth.instance.signOut();
      final success = await AuthService().signInWithGoogle();
      if (!success) {
        final details = AuthService.lastGoogleSignInError?.trim();
        setState(
          () => _message = details == null || details.isEmpty
              ? 'Google sign-in was not completed.'
              : 'Google sign-in was not completed: $details',
        );
        return;
      }

      final allowed = await _waitForDeveloperAccess();
      if (!allowed) {
        setState(
          () => _message =
              'Signed in, but this account is not currently marked role: developer.',
        );
        return;
      }

      setState(() => _message = 'Signed in with Google.');
    } catch (error) {
      setState(() => _message = 'Google sign-in failed: $error');
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _requestPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Enter the developer account email first.');
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Send password reset?',
      message: 'A secure password reset link will be sent to $email.',
      confirmLabel: 'Send reset link',
      icon: Icons.lock_reset_rounded,
    );
    if (!confirmed) return;

    setState(() => _authBusy = true);
    try {
      final result = await BackendAccountService.requestPasswordReset(
        email: email,
      );
      setState(
        () => _message = result.requestId.isEmpty
            ? 'Password reset request completed.'
            : 'Password reset link sent. Check the developer email within 5 minutes.',
      );
    } catch (error) {
      setState(() => _message = 'Password reset failed: $error');
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<bool> _isCurrentUserDeveloper() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));
    final data = doc.data();
    final role = (data?['role'] as String?)?.trim().toLowerCase();
    return role == 'developer' || data?['isDeveloper'] == true;
  }

  Future<bool> _waitForDeveloperAccess() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (await _isCurrentUserDeveloper()) return true;
      } catch (_) {
        // The access card handles missing or delayed role access for the user.
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return false;
  }

  Future<bool> _developerAccessFor(User user) {
    if (_developerAccessUid != user.uid || _developerAccessFuture == null) {
      _developerAccessUid = user.uid;
      _developerAccessFuture = _waitForDeveloperAccess();
    }
    return _developerAccessFuture!;
  }

  Future<void> _signOut() async {
    final confirmed = await _confirmAction(
      title: 'Sign out?',
      message:
          'You will need to sign in again before managing developer tools.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (!confirmed) return;

    await FirebaseAuth.instance.signOut();
    setState(() => _message = 'Signed out.');
  }

  Future<void> _deleteAuthUserCredentials(_DeveloperUser target) async {
    final confirmed = await _confirmAction(
      title: 'Delete login credentials?',
      message:
          'This deletes Firebase Auth sign-in credentials for ${target.displayName}, including email/password or Google sign-in, plus matching Firestore user data to avoid duplicate identities after re-registration.',
      confirmLabel: 'Delete credentials',
      icon: Icons.person_remove_alt_1_rounded,
      destructive: true,
    );
    if (!confirmed) return;

    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) {
      setState(() => _message = 'Sign in as a developer first.');
      return;
    }

    setState(() => _busyUserId = target.uid);
    try {
      final token = await admin.getIdToken(true);
      final backendUrl = _backendBaseUrl;
      final endpoint = Uri.parse('$backendUrl/developer-delete-user');
      final response = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'uid': target.uid, 'email': target.email}),
          )
          .timeout(const Duration(seconds: 20));

      final decoded = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['error'] ?? 'Delete request failed.');
      }

      await _writeDeveloperLog(
        action: 'delete_auth_credentials',
        target: target,
        details: {
          'deletedUid': data['deletedUid'],
          'deletedEmail': data['deletedEmail'],
          'deletedFirestorePaths': data['deletedFirestorePaths'],
        },
      );
      setState(
        () => _message =
            data['message'] as String? ??
            'Firebase Auth login credentials and Firestore user data were deleted.',
      );
    } catch (error) {
      setState(() => _message = 'Delete credentials failed: $error');
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _updateUserRole(_DeveloperUser target, String role) async {
    if (role == target.role) return;

    final confirmed = await _confirmAction(
      title: 'Update user role?',
      message:
          'Set ${target.displayName} to ${_roleLabel(role)}. This changes what the account can access.',
      confirmLabel: 'Update role',
      icon: Icons.admin_panel_settings_outlined,
    );
    if (!confirmed) return;

    setState(() => _busyUserId = target.uid);
    try {
      await FirebaseFirestore.instance.collection('users').doc(target.uid).set({
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _writeDeveloperLog(
        action: 'change_role',
        target: target,
        details: {'previousRole': target.role, 'newRole': role},
      );
      setState(() => _message = 'Updated ${target.displayName} role to $role.');
    } catch (error) {
      setState(() => _message = 'Role update failed: $error');
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _writeDeveloperLog({
    required String action,
    required _DeveloperUser target,
    required Map<String, Object?> details,
  }) async {
    final developer = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('developer_activity_logs').add({
      'action': action,
      'developerUid': developer?.uid,
      'developerEmail': developer?.email,
      'targetUid': target.uid,
      'targetEmail': target.email,
      'targetName': target.displayName,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    bool destructive = false,
  }) async {
    final accent = destructive
        ? const Color(0xFFDC2626)
        : const Color(0xFF2563EB);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: accent, size: 30),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF4B5563), height: 1.45),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
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
                child: const Text('Cancel'),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;

        return Scaffold(
          backgroundColor: const Color(0xFFF7F8FC),
          appBar: user == null
              ? null
              : AppBar(
                  title: const Text('FullBrightTrack Developer'),
                  centerTitle: false,
                  actions: [
                    IconButton(
                      tooltip: 'Developer activity',
                      onPressed: _openDeveloperActivityScreen,
                      icon: const Icon(Icons.history_rounded),
                    ),
                    IconButton(
                      tooltip: 'Account information',
                      onPressed: () => _openDeveloperAccountScreen(user),
                      icon: CircleAvatar(
                        radius: 15,
                        backgroundColor: const Color(0xFF2563EB),
                        child: Text(
                          (user.email ?? user.uid).characters.first
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth < 420
                    ? 12.0
                    : 16.0;

                return ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 16,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _hero(user),
                            const SizedBox(height: 14),
                            if (user == null)
                              _signInCard()
                            else
                              FutureBuilder<bool>(
                                future: _developerAccessFor(user),
                                builder: (context, accessSnapshot) {
                                  if (accessSnapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return _card(
                                      child: const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(18),
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                    );
                                  }
                                  if (accessSnapshot.data != true) {
                                    return _accessRequiredCard(user);
                                  }
                                  return Column(
                                    children: [_userDirectoryCard()],
                                  );
                                },
                              ),
                            if (_message != null) ...[
                              const SizedBox(height: 12),
                              _messageCard(_message!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _hero(User? user) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF0F766E)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_rounded, color: Colors.white),
          const SizedBox(height: 10),
          const Text(
            'Ops Studio',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            user == null
                ? 'Sign in with a developer account to manage user roles and login credentials.'
                : 'Signed in as ${user.email ?? user.uid}. Use the top bar for account details and activity logs.',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _signInCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Developer sign-in',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _authBusy ? null : _signIn,
            icon: _authBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: const Text('Sign in'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _authBusy ? null : _signInWithGoogle,
            icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
            label: const Text('Choose Google account'),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _authBusy ? null : _requestPasswordReset,
            icon: const Icon(Icons.lock_reset_rounded),
            label: const Text('Reset developer password'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeveloperAccountScreen(User user) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _DeveloperAccountScreen(user: user, onSignOut: _signOut),
      ),
    );
  }

  Future<void> _openDeveloperActivityScreen() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const _DeveloperActivityScreen()),
    );
  }

  Widget _accessRequiredCard(User user) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Color(0xFFF97316),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Developer access required',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${user.email ?? user.uid} is signed in, but Firestore does not currently show role: developer for this account.',
                      style: const TextStyle(
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await _confirmAction(
                title: 'Recheck developer access?',
                message:
                    'The app will read your current Firestore role again from the server.',
                confirmLabel: 'Recheck',
                icon: Icons.refresh_rounded,
              );
              if (!confirmed || !mounted) return;
              setState(() {
                _message = 'Checking developer access again...';
              });
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Recheck access'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Widget _userDirectoryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.manage_accounts_rounded,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User management',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Review all users, change roles, or delete login credentials.',
                      style: TextStyle(color: Colors.black54, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              final searchField = TextField(
                controller: _userSearchController,
                focusNode: _userSearchFocusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _applyUserSearch(),
                decoration: InputDecoration(
                  labelText: 'Search user name or email',
                  hintText: 'Type a name or email address',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: _applyUserSearch,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Search'),
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 112,
                    minHeight: 42,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              );
              final clearButton = _appliedUserSearch.isEmpty
                  ? null
                  : OutlinedButton.icon(
                      onPressed: _clearUserSearch,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Clear'),
                    );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    if (clearButton != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [clearButton],
                      ),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: searchField),
                  if (clearButton != null) ...[
                    const SizedBox(width: 10),
                    clearButton,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _emptyPanel(
                  icon: Icons.lock_outline_rounded,
                  text: 'Could not load users. Check developer role and rules.',
                );
              }

              final users =
                  (snapshot.data?.docs ?? const [])
                      .map(_DeveloperUser.fromDoc)
                      .toList()
                    ..sort(
                      (a, b) => a.displayName.toLowerCase().compareTo(
                        b.displayName.toLowerCase(),
                      ),
                    );
              if (users.isEmpty) {
                return _emptyPanel(
                  icon: Icons.people_outline_rounded,
                  text: 'No users found.',
                );
              }

              final query = _appliedUserSearch.trim().toLowerCase();
              final filteredUsers = query.isEmpty
                  ? users
                  : users.where((user) {
                      return user.displayName.toLowerCase().contains(query) ||
                          user.email.toLowerCase().contains(query);
                    }).toList();

              if (filteredUsers.isEmpty) {
                return _emptyPanel(
                  icon: Icons.person_search_rounded,
                  text: 'No users match "$_appliedUserSearch".',
                );
              }

              final totalPages =
                  ((filteredUsers.length - 1) ~/ _usersPerPage) + 1;
              final page = _currentUserPage.clamp(1, totalPages).toInt();
              final startIndex = (page - 1) * _usersPerPage;
              final endIndex = (startIndex + _usersPerPage).clamp(
                0,
                filteredUsers.length,
              );
              final visibleUsers = filteredUsers.sublist(startIndex, endIndex);
              final pageText = page.toString();
              if (_userPageController.text != pageText) {
                _userPageController.text = pageText;
                _userPageController.selection = TextSelection.collapsed(
                  offset: pageText.length,
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _userResultsSummary(
                    totalUsers: users.length,
                    filteredUsers: filteredUsers.length,
                    firstVisibleIndex: startIndex + 1,
                    lastVisibleIndex: endIndex,
                  ),
                  const SizedBox(height: 10),
                  for (final user in visibleUsers)
                    _DeveloperUserTile(
                      user: user,
                      busy: _busyUserId == user.uid,
                      onRoleChanged: (role) => _updateUserRole(user, role),
                      onDeleteCredentials: () =>
                          _deleteAuthUserCredentials(user),
                    ),
                  if (filteredUsers.length > _usersPerPage)
                    _userPaginationControls(
                      currentPage: page,
                      totalPages: totalPages,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _applyUserSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _appliedUserSearch = _userSearchController.text.trim();
      _currentUserPage = 1;
    });
  }

  void _clearUserSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _userSearchController.clear();
      _appliedUserSearch = '';
      _currentUserPage = 1;
    });
  }

  Widget _userResultsSummary({
    required int totalUsers,
    required int filteredUsers,
    required int firstVisibleIndex,
    required int lastVisibleIndex,
  }) {
    final searchActive = _appliedUserSearch.trim().isNotEmpty;
    final text = searchActive
        ? 'Showing $firstVisibleIndex-$lastVisibleIndex of $filteredUsers matches from $totalUsers users.'
        : 'Showing $firstVisibleIndex-$lastVisibleIndex of $totalUsers users.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
      ),
    );
  }

  Widget _userPaginationControls({
    required int currentPage,
    required int totalPages,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final pageField = SizedBox(
          width: 82,
          child: TextField(
            controller: _userPageController,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Page',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onSubmitted: (value) => _goToUserPage(value, totalPages),
            onEditingComplete: () =>
                _goToUserPage(_userPageController.text, totalPages),
          ),
        );
        final countText = Text(
          'of $totalPages',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        );
        final previousButton = currentPage == 1
            ? const SizedBox.shrink()
            : OutlinedButton.icon(
                onPressed: () => _setUserPage(currentPage - 1, totalPages),
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Previous'),
              );
        final nextButton = currentPage >= totalPages
            ? const SizedBox.shrink()
            : FilledButton(
                onPressed: () => _setUserPage(currentPage + 1, totalPages),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Next'),
                    SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded),
                  ],
                ),
              );

        if (compact) {
          return Container(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [pageField, const SizedBox(width: 10), countText],
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [previousButton, nextButton],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: previousButton,
                ),
              ),
              pageField,
              const SizedBox(width: 10),
              countText,
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: nextButton,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _setUserPage(int page, int totalPages) {
    setState(() {
      _currentUserPage = page.clamp(1, totalPages).toInt();
    });
  }

  void _goToUserPage(String value, int totalPages) {
    final page = int.tryParse(value.trim());
    _setUserPage(page ?? _currentUserPage, totalPages);
  }

  Widget _emptyPanel({required IconData icon, required String text}) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF2563EB)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _messageCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DeveloperUser {
  const _DeveloperUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.photoUrl,
    required this.rawData,
  });

  final String uid;
  final String displayName;
  final String email;
  final String role;
  final String? photoUrl;
  final Map<String, dynamic> rawData;

  factory _DeveloperUser.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final email = (data['email'] as String?)?.trim() ?? '';
    final rawName = (data['name'] as String?)?.trim();
    final displayName = rawName == null || rawName.isEmpty
        ? email.isEmpty
              ? doc.id
              : email.split('@').first
        : rawName;
    final role = ((data['role'] as String?) ?? 'user').trim().toLowerCase();

    return _DeveloperUser(
      uid: doc.id,
      displayName: displayName,
      email: email,
      role: role == 'admin' || role == 'developer' ? role : 'user',
      photoUrl: (data['photoUrl'] as String?)?.trim(),
      rawData: data,
    );
  }
}

class _DeveloperAccountScreen extends StatefulWidget {
  const _DeveloperAccountScreen({required this.user, required this.onSignOut});

  final User user;
  final Future<void> Function() onSignOut;

  @override
  State<_DeveloperAccountScreen> createState() =>
      _DeveloperAccountScreenState();
}

class _DeveloperAccountScreenState extends State<_DeveloperAccountScreen> {
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;

  User get user => FirebaseAuth.instance.currentUser ?? widget.user;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _addPasswordSignIn() async {
    final email = user.email;
    if (email == null || email.isEmpty) {
      _showMessage('No email address is linked to this developer account.');
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Add password sign-in?',
      message:
          'This lets this developer account sign in with either Google or email and password using $email.',
      confirmLabel: 'Add password',
      icon: Icons.add_moderator_outlined,
    );
    if (!confirmed) return;

    final password = await _showPasswordDialog();
    if (password == null) return;

    setState(() => _busy = true);
    try {
      await AuthService().linkPasswordToCurrentUser(email, password);
      await user.reload();
      if (!mounted) return;
      _showMessage('Password sign-in added.');
      setState(() {});
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showMessage(_accountErrorMessage(error, 'Could not add password.'));
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not add password: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPasswordReset() async {
    final email = user.email;
    if (email == null || email.isEmpty) {
      _showMessage('No email address is linked to this developer account.');
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Send password reset?',
      message: 'A secure password reset link will be sent to $email.',
      confirmLabel: 'Send reset link',
      icon: Icons.lock_reset_rounded,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final result = await BackendAccountService.requestPasswordReset(
        email: email,
      );
      if (!mounted) return;
      _showMessage(
        result.requestId.isEmpty
            ? 'Password reset request completed.'
            : 'Password reset link sent. Check the developer email within 5 minutes.',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Password reset failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkGoogleSignIn() async {
    final email = user.email;
    if (email == null || email.isEmpty) {
      _showMessage('No email address is linked to this developer account.');
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Verify with Google Sign-In?',
      message:
          'Choose the Google account for $email. After verification, this developer account can also use Google Sign-In.',
      confirmLabel: 'Verify with Google',
      icon: Icons.g_mobiledata_rounded,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await AuthService().linkGoogleToCurrentUser();
      await user.reload();
      if (!mounted) return;
      _showMessage('Google Sign-In verified for this developer account.');
      setState(() {});
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showMessage(_accountErrorMessage(error, 'Could not verify Google.'));
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not verify Google: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _accountErrorMessage(FirebaseAuthException error, String fallback) {
    switch (error.code) {
      case 'provider-already-linked':
        return 'This sign-in method is already linked.';
      case 'credential-already-in-use':
        return 'That sign-in method is already linked to another account.';
      case 'requires-recent-login':
        return 'Please sign out, sign in again, then retry.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'email-mismatch':
        return error.message ?? 'Please choose the matching Google account.';
      default:
        return error.message ?? fallback;
    }
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
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              icon: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.add_moderator_outlined,
                  color: Color(0xFF2563EB),
                  size: 30,
                ),
              ),
              title: const Text(
                'Add password',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Create a password for this developer account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF4B5563), height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setDialogState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final password = _passwordController.text.trim();
                      if (password.length < 6) {
                        _showMessage('Password must be at least 6 characters.');
                        return;
                      }
                      Navigator.pop(context, password);
                    },
                    child: const Text('Add password'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB), size: 30),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF4B5563), height: 1.45),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
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
    final email = user.email ?? 'No email';
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : email;
    final providers = user.providerData.map((info) => info.providerId).toSet();
    final hasPassword = providers.contains('password');
    final hasGoogle = providers.contains('google.com');

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(title: const Text('Account information')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: const Color(0xFF2563EB),
                    child: Text(
                      email.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 18),
                  _AccountInfoRow(label: 'UID', value: user.uid),
                  _AccountInfoRow(
                    label: 'Providers',
                    value: providers.map(_providerLabel).join(', '),
                  ),
                  const SizedBox(height: 18),
                  if (!hasPassword && hasGoogle)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _addPasswordSignIn,
                      icon: const Icon(Icons.add_moderator_outlined),
                      label: const Text('Add password'),
                    )
                  else if (hasPassword && !hasGoogle)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _linkGoogleSignIn,
                          icon: const Icon(
                            Icons.g_mobiledata_rounded,
                            size: 28,
                          ),
                          label: const Text('Verify with Google Sign-In'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _requestPasswordReset,
                          icon: const Icon(Icons.lock_reset_rounded),
                          label: const Text('Reset password'),
                        ),
                      ],
                    )
                  else if (hasPassword)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _requestPasswordReset,
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: const Text('Reset password'),
                    ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      await widget.onSignOut();
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Logout'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _providerLabel(String providerId) {
    return providerId == 'google.com'
        ? 'Google'
        : providerId == 'password'
        ? 'Password'
        : providerId;
  }
}

class _AccountInfoRow extends StatelessWidget {
  const _AccountInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? 'Not available' : value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperUserTile extends StatelessWidget {
  const _DeveloperUserTile({
    required this.user,
    required this.busy,
    required this.onRoleChanged,
    required this.onDeleteCredentials,
  });

  final _DeveloperUser user;
  final bool busy;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onDeleteCredentials;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: user.photoUrl == null || user.photoUrl!.isEmpty
                    ? null
                    : NetworkImage(user.photoUrl!),
                child: user.photoUrl == null || user.photoUrl!.isEmpty
                    ? Text(user.displayName.characters.first.toUpperCase())
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      user.email.isEmpty ? user.uid : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      user.uid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'View profile data',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            children: [_ProfileDataPanel(user: user)],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.admin_panel_settings_outlined,
              color: Color(0xFF2563EB),
            ),
            title: Text(
              'Role and access: ${_roleLabel(user.role)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 2, bottom: 6),
                    child: Text(
                      'Available role',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: user.role,
                    decoration: InputDecoration(
                      hintText: 'Select role',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(
                        value: 'developer',
                        child: Text('Developer'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) {
                            if (value != null) onRoleChanged(value);
                          },
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onDeleteCredentials,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_remove_alt_1_rounded),
                    label: const Text('Delete login credentials'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileDataPanel extends StatelessWidget {
  const _ProfileDataPanel({required this.user});

  final _DeveloperUser user;

  @override
  Widget build(BuildContext context) {
    final extraFields = user.rawData.entries
        .where((entry) => !_hiddenKeys.contains(entry.key))
        .take(10)
        .toList();
    final visibleData = <MapEntry<String, Object?>>[
      MapEntry('uid', user.uid),
      MapEntry('name', user.displayName),
      MapEntry('email', user.email.isEmpty ? 'Not provided' : user.email),
      MapEntry('role', _roleLabel(user.role)),
      ...extraFields,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Firestore profile',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${user.rawData.length} stored fields',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in visibleData)
            _ProfileDataRow(
              label: entry.key,
              value: _profileValue(entry.value),
            ),
          if (extraFields.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'No additional profile fields are stored for this account yet.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ),
          if (user.rawData.length > visibleData.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${user.rawData.length - visibleData.length} more fields hidden to keep this view readable.',
                style: const TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  static const _hiddenKeys = {
    'uid',
    'name',
    'email',
    'role',
    'photoUrl',
    'isAdmin',
    'isDeveloper',
  };

  static String _profileValue(Object? value) {
    if (value == null) return 'Not set';
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is Iterable || value is Map) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    final text = value.toString().trim();
    return text.isEmpty ? 'Not set' : text;
  }
}

class _ProfileDataRow extends StatelessWidget {
  const _ProfileDataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _prettyLabel(label),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              softWrap: true,
              overflow: TextOverflow.fade,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _prettyLabel(String value) {
    final spaced = value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .trim();
    if (spaced.isEmpty) return 'Field';
    return spaced
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}

class _DeveloperLogTile extends StatelessWidget {
  const _DeveloperLogTile({required this.data, required this.id});

  final Map<String, dynamic> data;
  final String id;

  @override
  Widget build(BuildContext context) {
    final action = (data['action'] as String?) ?? 'developer_action';
    final developer = (data['developerEmail'] as String?) ?? 'unknown';
    final target = (data['targetEmail'] as String?)?.trim().isNotEmpty == true
        ? data['targetEmail'] as String
        : (data['targetName'] as String?) ??
              (data['targetUid'] as String?) ??
              '';
    final createdAt = data['createdAt'];
    final actionLabel = action == 'change_role'
        ? 'Changed user role'
        : action == 'delete_auth_credentials'
        ? 'Deleted login credentials'
        : action.replaceAll('_', ' ');
    final description = action == 'change_role'
        ? '$developer updated $target'
        : action == 'delete_auth_credentials'
        ? '$developer removed sign-in access for $target'
        : '$developer performed an action for $target';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_rounded, color: Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(color: Colors.black54, height: 1.3),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDeveloperLogTime(createdAt),
                  style: const TextStyle(color: Colors.black38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperActivityScreen extends StatelessWidget {
  const _DeveloperActivityScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(title: const Text('Developer activity')),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('developer_activity_logs')
              .orderBy('createdAt', descending: true)
              .limit(80)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('Could not load activity logs.'));
            }
            final logs = snapshot.data?.docs ?? const [];
            if (logs.isEmpty) {
              return const Center(child: Text('No developer activity yet.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final log = logs[index];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: _DeveloperLogTile(data: log.data(), id: log.id),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'developer':
      return 'Developer';
    case 'admin':
      return 'Admin';
    default:
      return 'User';
  }
}

String _formatDeveloperLogTime(Object? value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is String) date = DateTime.tryParse(value);
  if (date == null) return 'pending timestamp';
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour:$minute:$second';
}
