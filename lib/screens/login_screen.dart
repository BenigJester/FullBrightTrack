import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/backend_account_service.dart';
import 'consent_screen.dart';
import 'register_screen.dart';

class LoginTab extends StatefulWidget {
  const LoginTab({super.key});

  @override
  State<LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends State<LoginTab>
    with SingleTickerProviderStateMixin {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final auth = AuthService();

  bool isLoading = false;
  bool obscurePassword = true;
  bool rawDataConsent = false;
  late final AnimationController _consentAttentionController;
  late final Animation<double> _consentShake;

  @override
  void initState() {
    super.initState();
    _consentAttentionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 430),
    );
    _consentShake =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 10, end: -7), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -7, end: 7), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 7, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(
            parent: _consentAttentionController,
            curve: Curves.easeOut,
          ),
        );
  }

  Future<void> createUserIfNotExists() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

    final doc = await ref.get();

    if (!doc.exists) {
      await ref.set({
        'email': user.email,
        'name': user.displayName,
        'photoUrl': user.photoURL,
        'role': 'user',
        'rawAiDataConsent': rawDataConsent,
        'rawAiDataConsentAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else if (rawDataConsent) {
      await ref.set({
        'rawAiDataConsent': true,
        'rawAiDataConsentAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  bool _requireRawDataConsent() {
    if (rawDataConsent) return true;

    HapticFeedback.mediumImpact();
    _consentAttentionController.forward(from: 0);
    showErrorSnackBar(
      'Please agree to raw wellness data processing before continuing.',
    );
    return false;
  }

  Future<void> _openConsentScreen() async {
    if (isLoading) return;

    final agreed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ConsentScreen()),
    );

    if (!mounted) return;
    if (agreed == true) {
      setState(() => rawDataConsent = true);
    }
  }

  Future<void> login() async {
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }

      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      // ================= VALIDATION =================

      if (!_requireRawDataConsent()) {
        return;
      }

      if (email.isEmpty || password.isEmpty) {
        showErrorSnackBar('Please enter email and password');
        return;
      }

      // ================= LOGIN =================

      await auth.login(email, password);
      await createUserIfNotExists();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        showErrorSnackBar(_getErrorMessage(e));
      }
    } on PlatformException catch (_) {
      if (mounted) {
        showErrorSnackBar('Authentication service temporarily unavailable');
      }
    } catch (e) {
      debugPrint('Login Error: $e');

      if (mounted) {
        showErrorSnackBar('Unable to login right now. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _consentAttentionController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> googleLogin() async {
    try {
      if (!_requireRawDataConsent()) {
        return;
      }

      if (mounted) {
        setState(() => isLoading = true);
      }

      final success = await auth.signInWithGoogle();

      if (success) {
        await createUserIfNotExists();
      } else if (AuthService.pendingGoogleCredential != null) {
        await _confirmAndLinkExistingPasswordAccount();
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(_getErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _confirmAndLinkExistingPasswordAccount() async {
    final googleEmail = AuthService.pendingGoogleEmail?.trim();
    final email = googleEmail?.isNotEmpty == true
        ? googleEmail!
        : emailController.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0EA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.link_rounded,
            color: Color(0xFFFF7A59),
            size: 32,
          ),
        ),
        title: const Text(
          'Link existing account?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '$email already has an email/password account. Sign in with the password for this email to link Google Sign-In to the same account.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700, height: 1.45),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFFFF7A59),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Link with password'),
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
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    emailController.text = email;
    final password = passwordController.text.trim();
    if (password.isEmpty) {
      showErrorSnackBar('Enter your password first, then try Google again.');
      return;
    }

    try {
      await auth.login(email, password);
      final credential = AuthService.pendingGoogleCredential;
      if (credential == null) return;
      await auth.linkGoogleToCurrentUser(googleCredential: credential);
      await createUserIfNotExists();
      if (mounted) showErrorSnackBar('Google Sign-In linked to your account');
    } on FirebaseAuthException catch (e) {
      if (mounted) showErrorSnackBar(_getErrorMessage(e));
    }
  }

  Future<void> _requestPasswordReset() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      showErrorSnackBar('Enter your email address first.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0EA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.lock_reset_rounded,
            color: Color(0xFFFF7A59),
            size: 32,
          ),
        ),
        title: const Text(
          'Reset password?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'We will send a secure password reset link to $email.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700, height: 1.45),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A59),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Send reset link'),
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
      ),
    );
    if (confirmed != true) return;

    try {
      setState(() => isLoading = true);
      final result = await BackendAccountService.requestPasswordReset(
        email: email,
      );
      if (!mounted) return;
      showErrorSnackBar(
        result.requestId.isEmpty
            ? 'Password reset request completed.'
            : 'Password reset link sent. Check your email within 5 minutes.',
      );
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
                size: 22,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getErrorMessage(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Invalid email address';

        case 'user-not-found':
          return 'No account found with this email';

        case 'wrong-password':
          return 'Incorrect password';

        case 'invalid-credential':
          return 'Incorrect email or password';

        case 'email-already-in-use':
          return 'Email is already registered';

        case 'weak-password':
          return 'Password is too weak';

        case 'network-request-failed':
          return 'No internet connection';

        case 'too-many-requests':
          return 'Too many attempts. Try again later';

        default:
          return e.message ?? 'Authentication failed';
      }
    }

    return 'Something went wrong';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 40,
            ),
            child: Column(
              children: [
                const SizedBox(height: 28),

                // ================= LOGO =================
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9966), Color(0xFFFF5E62)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),

                const SizedBox(height: 28),

                // ================= TITLE =================
                const Text(
                  "Welcome Back",
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E1E1E),
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  "Login to continue your wellness journey",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 40),

                // ================= EMAIL =================
                _inputField(
                  controller: emailController,
                  hint: "Email Address",
                  icon: Icons.email_outlined,
                ),

                const SizedBox(height: 18),

                // ================= PASSWORD =================
                _inputField(
                  controller: passwordController,
                  hint: "Password",
                  icon: Icons.lock_outline_rounded,
                  obscure: obscurePassword,
                  suffix: IconButton(
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });

                      HapticFeedback.lightImpact();
                    },
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: isLoading ? null : _requestPasswordReset,
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: Color(0xFFFF7A59),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                AnimatedBuilder(
                  animation: _consentShake,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(_consentShake.value, 0),
                      child: child,
                    );
                  },
                  child: _rawDataConsentCard(),
                ),

                const SizedBox(height: 20),

                // ================= LOGIN BUTTON =================
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : login,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFFF7A59),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "Login",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 18),

                // ================= DIVIDER =================
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        "OR",
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),

                const SizedBox(height: 18),

                // ================= GOOGLE BUTTON =================
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : googleLogin,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: Image.network(
                      "https://cdn-icons-png.flaticon.com/512/2991/2991148.png",
                      width: 22,
                    ),
                    label: const Text(
                      "Continue with Google",
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // ================= REGISTER =================
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account?",
                      style: TextStyle(color: Colors.grey.shade700),
                    ),

                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RegisterTab(),
                          ),
                        );
                      },
                      child: const Text(
                        "Register",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF7A59),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= INPUT =================

  Widget _rawDataConsentCard() {
    final borderColor = rawDataConsent
        ? Colors.green
        : _consentAttentionController.isAnimating
        ? Colors.redAccent
        : Colors.grey.shade300;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: rawDataConsent
            ? () => setState(() => rawDataConsent = false)
            : _openConsentScreen,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor,
              width: rawDataConsent ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: rawDataConsent,
                activeColor: Colors.green,
                onChanged: (value) {
                  if (rawDataConsent) {
                    setState(() => rawDataConsent = false);
                  } else {
                    _openConsentScreen();
                  }
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rawDataConsent
                          ? 'Privacy Policy acknowledged'
                          : 'I have read and acknowledge the PRIVACY POLICY',
                      style: TextStyle(
                        color: rawDataConsent
                            ? Colors.green.shade700
                            : Colors.grey.shade900,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (rawDataConsent) ...[
                      const SizedBox(height: 3),
                      Text(
                        'You can continue using FullBrightTrack with wellness analysis and safety support enabled.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.2,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            offset: const Offset(0, 4),
            color: Colors.black.withValues(alpha: 0.04),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon),
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}
