import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/backend_account_service.dart';

class RegisterTab extends StatefulWidget {
  const RegisterTab({super.key});

  @override
  State<RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<RegisterTab> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final auth = AuthService();

  bool obscurePassword = true;
  bool isLoading = false;

  Future<void> register() async {
    final email = emailController.text.trim();

    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      HapticFeedback.mediumImpact();

      final messenger = ScaffoldMessenger.of(context);

      messenger.clearSnackBars();

      messenger.showSnackBar(
        SnackBar(
          content: const Text("Please fill all fields"),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
      return;
    }

    if (password.length < 6) {
      HapticFeedback.mediumImpact();

      final messenger = ScaffoldMessenger.of(context);

      messenger.clearSnackBars();

      messenger.showSnackBar(
        SnackBar(
          content: const Text("Password must be at least 6 characters"),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      final confirmation = await BackendAccountService.startRegistration(
        email: email,
      );

      if (!mounted) return;
      await _showConfirmationStartedDialog(confirmation, password);
    } on FirebaseAuthException catch (e) {
      if (FirebaseAuth.instance.currentUser?.email == email) {
        await FirebaseAuth.instance.signOut();
      }

      if (!mounted) return;

      if (e.code == 'email-already-in-use') {
        await _confirmAndMergeGoogleAccount(email, password);
      } else {
        _showSnackBar(_authErrorMessage(e));
      }
    } catch (e) {
      if (FirebaseAuth.instance.currentUser?.email == email) {
        await FirebaseAuth.instance.signOut();
      }
      if (!mounted) return;
      _showSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _showConfirmationStartedDialog(
    PendingRegistrationResult confirmation,
    String password,
  ) async {
    var isCreatingAccount = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final expiresAt = confirmation.expiresAt;
        final expiryText = expiresAt == null
            ? 'This link will expire soon.'
            : 'Expires at ${TimeOfDay.fromDateTime(expiresAt.toLocal()).format(context)}.';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> createConfirmedAccount() async {
              final dialogNavigator = Navigator.of(context);
              final rootNavigator = Navigator.of(this.context);
              setDialogState(() => isCreatingAccount = true);
              var shouldUpdateDialog = true;
              try {
                await BackendAccountService.completeRegistration(
                  requestId: confirmation.requestId,
                  email: confirmation.email,
                );
                await auth.register(confirmation.email, password);
                await FirebaseAuth.instance.signOut();

                if (!mounted) return;
                shouldUpdateDialog = false;
                dialogNavigator.pop();
                rootNavigator.pop();
                _showSnackBar(
                  'Email confirmed. You can now sign in with your account.',
                );
              } on FirebaseAuthException catch (e) {
                if (FirebaseAuth.instance.currentUser?.email ==
                    confirmation.email) {
                  await FirebaseAuth.instance.signOut();
                }

                if (!mounted) return;
                _showSnackBar(_authErrorMessage(e));
              } catch (e) {
                if (!mounted) return;
                _showSnackBar(e.toString());
              } finally {
                if (mounted && shouldUpdateDialog) {
                  setDialogState(() => isCreatingAccount = false);
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              icon: Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0EA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_rounded,
                  color: Color(0xFFFF7A59),
                  size: 32,
                ),
              ),
              title: const Text(
                'Confirm your registration',
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'A confirmation link was sent to ${confirmation.email}. Open it from your email inbox, then return here to create the account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      expiryText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              actions: [
                if (confirmation.confirmationUrl.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isCreatingAccount
                          ? null
                          : () async {
                              final uri = Uri.parse(
                                confirmation.confirmationUrl,
                              );
                              final opened = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!opened && mounted) {
                                _showSnackBar(
                                  'Could not open confirmation link',
                                );
                              }
                            },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open Confirmation Link'),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFFFF7A59),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isCreatingAccount
                        ? null
                        : createConfirmedAccount,
                    icon: isCreatingAccount
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      isCreatingAccount
                          ? 'Creating Account...'
                          : 'I Confirmed, Create Account',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF7A59),
                      side: const BorderSide(color: Color(0xFFFF7A59)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: isCreatingAccount
                        ? null
                        : () {
                            Navigator.pop(context);
                            Navigator.pop(this.context);
                          },
                    child: const Text('Back to Login'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmAndMergeGoogleAccount(
    String email,
    String password,
  ) async {
    final shouldMerge = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Account already exists"),
          content: Text(
            "$email is already used by another sign-in method. "
            "Sign in with Google to add this password to the same account?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Continue"),
            ),
          ],
        );
      },
    );

    if (shouldMerge != true) return;

    try {
      final success = await auth.signInWithGoogle();

      if (!mounted) return;

      if (!success) {
        _showSnackBar("Google sign-in was cancelled");
        return;
      }

      final user = FirebaseAuth.instance.currentUser;

      if (user?.email?.toLowerCase() != email.toLowerCase()) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        _showSnackBar("Please choose the Google account that uses $email");
        return;
      }

      final hasPassword =
          user?.providerData.any((info) => info.providerId == 'password') ??
          false;

      if (!hasPassword) {
        await auth.linkPasswordToCurrentUser(email, password);
        await user?.reload();
      }

      if (!mounted) return;

      _showSnackBar(
        "Account merged. You can now sign in with Google or password",
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnackBar(_authErrorMessage(e));
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Could not merge account");
      debugPrint("Account merge error: $e");
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Password is too weak';
      case 'invalid-email':
        return 'Invalid email address';
      case 'network-request-failed':
        return 'No internet connection';
      case 'provider-already-linked':
        return 'Password sign-in is already enabled';
      case 'requires-recent-login':
        return 'Please sign in with Google again, then retry';
      default:
        return e.message ?? 'Unable to create account';
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),

        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              height: MediaQuery.of(context).size.height - 40,
              child: Column(
                children: [
                  // ================= BACK =================
                  // Align(
                  //   alignment: Alignment.centerLeft,
                  //   child: Padding(
                  //     padding: const EdgeInsets.only(top: 12),
                  //     child: IconButton(
                  //       onPressed: () {
                  //         Navigator.pop(context);
                  //       },
                  //       icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  //     ),
                  //   ),
                  // ),
                  const Spacer(),

                  // ================= ICON =================
                  Container(
                    width: 95,
                    height: 95,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB347), Color(0xFFFF5E62)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ================= TITLE =================
                  const Text(
                    "Create Account",
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "Start building better habits and track your wellness journey.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.grey.shade600,
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
                        HapticFeedback.lightImpact();

                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ================= PASSWORD HINT =================
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),

                      const SizedBox(width: 6),

                      Text(
                        "Use at least 6 characters",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // ================= REGISTER BUTTON =================
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : register,
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
                              "Create Account",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ================= LOGIN =================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Already have an account?",
                        style: TextStyle(color: Colors.grey.shade700),
                      ),

                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text(
                          "Login",
                          style: TextStyle(
                            color: Color(0xFFFF7A59),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================= INPUT FIELD =================

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
