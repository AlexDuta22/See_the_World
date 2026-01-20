import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:see_the_world/components/my_textfield.dart';

import '../components/my_button.dart';
import '../components/square_tile.dart';
import '../services/shared_pref.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  Future<void>? _googleInitFuture;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> signUserIn() async {
    bool loadingVisible = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    loadingVisible = true;

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: emailController.text.trim())
          .limit(1)
          .get();
      String myname = '';
      String myid = '';
      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        myname = data['name']?.toString() ?? '';
        myid = data['id']?.toString() ?? '';
      }
      if (myname.isNotEmpty) {
        await SharedpreferenceHelper().saveUserDisplayName(myname);
      }
      if (myid.isNotEmpty) {
        await SharedpreferenceHelper().saveUserId(myid);
      }
      await SharedpreferenceHelper()
          .saveUserEmail(emailController.text.trim());
      if (mounted && loadingVisible) {
        Navigator.of(context).pop();
        loadingVisible = false;
      }
    } on FirebaseAuthException catch (e) {
      if (mounted && loadingVisible) {
        Navigator.of(context).pop();
        loadingVisible = false;
      }
      // Give clearer feedback when credentials are wrong so the user can retry.
      final message = (e.code == 'wrong-password' || e.code == 'user-not-found')
          ? 'Incorrect email or password. Please try again.'
          : (e.code == 'invalid-email')
              ? 'That email looks invalid. Please check and try again.'
              : (e.message ?? 'Failed to sign in.');
      _showErrorMessage(message);
    } catch (_) {
      if (mounted && loadingVisible) {
        Navigator.of(context).pop();
        loadingVisible = false;
      }
      _showErrorMessage('Something went wrong. Please try again.');
    }
  }

  Future<void> _ensureGoogleInitialized() {
    _googleInitFuture ??= GoogleSignIn.instance.initialize();
    return _googleInitFuture!;
  }

  Future<void> signInWithGoogle() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await _ensureGoogleInitialized();
      final GoogleSignInAccount googleUser =
          await GoogleSignIn.instance.authenticate();
      final GoogleSignInAuthentication googleAuth =
          googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return;
      }
      _showErrorMessage(e.description ?? 'Google sign-in failed.');
    } on FirebaseAuthException catch (e) {
      _showErrorMessage(e.message ?? 'Google sign-in failed.');
    } catch (_) {
      _showErrorMessage('Something went wrong with Google sign-in.');
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> signInWithFacebook() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final LoginResult result = await FacebookAuth.instance.login();
      if (result.status != LoginStatus.success || result.accessToken == null) {
        if (mounted) Navigator.of(context).pop();
        if (result.status == LoginStatus.cancelled) return;
        final message = result.message ?? 'Facebook sign-in failed.';
        _showErrorMessage(message);
        return;
      }

      final credential = FacebookAuthProvider.credential(
        result.accessToken!.tokenString,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _showErrorMessage(e.message ?? 'Facebook sign-in failed.');
    } catch (_) {
      _showErrorMessage('Something went wrong with Facebook sign-in.');
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sign in error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showErrorMessage('Enter your email to reset your password.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Check your email'),
          content: Text('We sent a reset link to $email.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      final message = (e.code == 'user-not-found')
          ? 'No user found for that email.'
          : (e.code == 'invalid-email')
              ? 'That email address looks invalid.'
              : (e.message ?? 'Could not send reset email (${e.code}).');
      _showErrorMessage(message);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      _showErrorMessage('Could not send reset email. Try again later.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 50),
                Image.asset(
                  'lib/images/app_icon.png',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 50),
                Text(
                  'Welcome back you\'ve been missed!',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 25),
                MyTextField(
                  controller: emailController,
                  hintText: 'Email',
                  obscureText: false,
                ),
                const SizedBox(height: 10),
                MyTextField(
                  controller: passwordController,
                  hintText: 'Password',
                  obscureText: true,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _resetPassword,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(color: Colors.blue[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                MyButton(
                  onTap: signUserIn,
                  text: 'Sign In',
                ),
                const SizedBox(height: 50),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(
                          thickness: 0.5,
                          color: Colors.grey[400],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          'Or continue with',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          thickness: 0.5,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SquareTile(
                      imagePath: 'lib/images/google.png',
                      onTap: signInWithGoogle,
                    ),
                    const SizedBox(width: 25),
                    SquareTile(
                      imagePath: 'lib/images/facebook.png',
                      onTap: signInWithFacebook,
                    ),
                  ],
                ),
                const SizedBox(height: 50),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Not a member?',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegisterPage(),
                          ),
                        );
                      },
                      child: const Text(
                        'Register now',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
