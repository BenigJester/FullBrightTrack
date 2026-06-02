import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FullBrightDeveloperConsoleApp());
}

class FullBrightDeveloperConsoleApp extends StatelessWidget {
  const FullBrightDeveloperConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FullBrightTrack Developer Console',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
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
  static const _collections = [
    'users',
    'admin_monitoring',
    'admin_alerts',
    'admin_fcm_tokens',
    'leaderboard',
  ];

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pathController = TextEditingController();
  final _jsonController = TextEditingController();
  final _targetUidController = TextEditingController();
  final _targetEmailController = TextEditingController();

  String _collection = _collections.first;
  String? _message;
  bool _authBusy = false;
  bool _saving = false;
  bool _deletingAuthUser = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    _jsonController.dispose();
    _targetUidController.dispose();
    _targetEmailController.dispose();
    super.dispose();
  }

  String get _backendBaseUrl {
    const configured = String.fromEnvironment('FULLBRIGHT_BACKEND_URL');
    if (configured.trim().isNotEmpty) {
      return configured.trim().replaceAll(RegExp(r'/+$'), '');
    }

    const stressUrl = String.fromEnvironment('GENKIT_STRESS_FLOW_URL');
    final stressUri = Uri.tryParse(stressUrl.trim());
    if (stressUri != null) {
      final segments = stressUri.pathSegments.where((part) => part != 'stress');
      return stressUri
          .replace(pathSegments: segments, query: '', fragment: '')
          .toString()
          .replaceAll(RegExp(r'/+$'), '');
    }

    const debugUrl = String.fromEnvironment(
      'FULLBRIGHT_BACKEND_DEBUG_URL',
      defaultValue: 'http://10.0.2.2:8080',
    );
    return debugUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  DocumentReference<Map<String, dynamic>>? get _selectedDoc {
    final path = _pathController.text.trim();
    if (path.isEmpty || !path.contains('/')) return null;
    return FirebaseFirestore.instance.doc(path);
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = 'Enter admin email and password.');
      return;
    }

    setState(() => _authBusy = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      setState(() => _message = 'Signed in. Firestore rules still apply.');
    } catch (error) {
      setState(() => _message = 'Sign-in failed: $error');
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    _jsonController.clear();
    setState(() => _message = 'Signed out.');
  }

  Future<void> _loadPath(String path) async {
    _pathController.text = path;
    final ref = _selectedDoc;
    if (ref == null) {
      setState(() => _message = 'Use a document path like users/userId.');
      return;
    }

    try {
      final doc = await ref.get();
      _jsonController.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(doc.data() ?? <String, dynamic>{});
      setState(
        () => _message = doc.exists ? 'Document loaded.' : 'New document.',
      );
    } catch (error) {
      setState(() => _message = 'Could not load document: $error');
    }
  }

  Future<void> _save() async {
    final ref = _selectedDoc;
    if (ref == null) {
      setState(() => _message = 'Enter a document path first.');
      return;
    }

    setState(() => _saving = true);
    try {
      final decoded = jsonDecode(_jsonController.text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON must be an object');
      }
      await ref.set(decoded, SetOptions(merge: true));
      setState(() => _message = 'Saved with merge.');
    } catch (error) {
      setState(() => _message = 'Save failed: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ref = _selectedDoc;
    if (ref == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('This deletes ${ref.path}. Firestore rules apply.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.delete();
      _jsonController.clear();
      setState(() => _message = 'Document deleted.');
    } catch (error) {
      setState(() => _message = 'Delete failed: $error');
    }
  }

  Future<void> _deleteAuthUserCredentials() async {
    final uid = _targetUidController.text.trim();
    final email = _targetEmailController.text.trim();
    if (uid.isEmpty && email.isEmpty) {
      setState(() => _message = 'Enter a target user UID or email.');
      return;
    }

    final description = uid.isNotEmpty ? uid : email;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete login credentials?'),
        content: Text(
          'This deletes Firebase Auth sign-in credentials for $description, including email/password or Google sign-in. Firestore profile data is not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete credentials'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) {
      setState(() => _message = 'Sign in as an admin first.');
      return;
    }

    setState(() => _deletingAuthUser = true);
    try {
      final token = await admin.getIdToken(true);
      final response = await http
          .post(
            Uri.parse('$_backendBaseUrl/developer-delete-user'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'uid': uid, 'email': email}),
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

      _targetUidController.clear();
      _targetEmailController.clear();
      setState(
        () => _message =
            data['message'] as String? ??
            'Firebase Auth login credentials were deleted.',
      );
    } catch (error) {
      setState(() => _message = 'Delete credentials failed: $error');
    } finally {
      if (mounted) setState(() => _deletingAuthUser = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;

        return Scaffold(
          backgroundColor: const Color(0xFFF7F8FC),
          appBar: AppBar(
            title: const Text('FullBrightTrack Dev'),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            actions: [
              if (user != null)
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout_rounded),
                ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _hero(user),
                const SizedBox(height: 14),
                if (user == null)
                  _signInCard()
                else ...[
                  _userManagementCard(),
                  const SizedBox(height: 14),
                  _consoleCard(),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  _messageCard(_message!),
                ],
              ],
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
          colors: [Color(0xFFFF8A65), Color(0xFFFF7043)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
          const SizedBox(height: 10),
          const Text(
            'Developer Console',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            user == null
                ? 'Sign in with an admin account to manage Firestore documents.'
                : 'Signed in as ${user.email ?? user.uid}. Firestore rules still protect every action.',
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
            'Admin sign-in',
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
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
              border: OutlineInputBorder(),
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
        ],
      ),
    );
  }

  Widget _userManagementCard() {
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
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.manage_accounts_rounded,
                  color: Colors.redAccent,
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
                      'Delete Firebase Auth login credentials by UID or email.',
                      style: TextStyle(color: Colors.black54, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _targetUidController,
            decoration: const InputDecoration(
              labelText: 'Target UID',
              hintText: 'Firebase Auth UID',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _targetEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Target email',
              hintText: 'student@example.com',
              prefixIcon: Icon(Icons.alternate_email_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'This removes sign-in access from Firebase Auth, including email/password and Google providers. Firestore documents are kept unless you delete them separately below.',
              style: TextStyle(color: Color(0xFF8A3A24), height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _deletingAuthUser ? null : _deleteAuthUserCredentials,
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            icon: _deletingAuthUser
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_remove_alt_1_rounded),
            label: Text(
              _deletingAuthUser
                  ? 'Deleting credentials...'
                  : 'Delete login credentials',
            ),
          ),
        ],
      ),
    );
  }

  Widget _consoleCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _collection,
            decoration: const InputDecoration(
              labelText: 'Browse collection',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in _collections)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _collection = value);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(height: 220, child: _collectionList()),
          const SizedBox(height: 12),
          TextField(
            controller: _pathController,
            decoration: InputDecoration(
              labelText: 'Document path',
              hintText: 'users/userId',
              prefixIcon: const Icon(Icons.route_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: () => _loadPath(_pathController.text.trim()),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _jsonController,
            minLines: 10,
            maxLines: 18,
            decoration: const InputDecoration(
              labelText: 'JSON editor',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('Save merge'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete document'),
          ),
        ],
      ),
    );
  }

  Widget _collectionList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(_collection)
          .limit(25)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _emptyPanel(
            icon: Icons.lock_outline_rounded,
            text:
                'Could not load $_collection. Check that this signed-in account is allowed by Firestore rules.',
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return _emptyPanel(
            icon: Icons.inbox_outlined,
            text: 'No visible documents in $_collection.',
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            return Card(
              elevation: 0,
              child: ListTile(
                dense: true,
                title: Text(doc.id, overflow: TextOverflow.ellipsis),
                subtitle: Text('$_collection/${doc.id}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _loadPath('$_collection/${doc.id}'),
              ),
            );
          },
        );
      },
    );
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
          Icon(icon, color: Colors.deepOrange),
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
