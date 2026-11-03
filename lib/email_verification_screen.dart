import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String? pendingAlbumName;
  final int? pendingSongIndex;

  const EmailVerificationScreen({
    super.key,
    this.pendingAlbumName,
    this.pendingSongIndex,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();
  bool _isChecking = false;

  Future<void> _checkVerification() async {
    if (!mounted) return;
    setState(() => _isChecking = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final bool confirmed = prefs.getBool('email_confirmed') ?? false;

    print("🔍 Button pressed - Confirmed in prefs: $confirmed");

    if (confirmed) {
      _navigateToHome();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Still false. Try the Debug button below."),
          backgroundColor: Colors.orange,
        ),
      );
    }

    if (mounted) setState(() => _isChecking = false);
  }

  // === MANUAL DEBUG BUTTON ===
  Future<void> _forceVerifiedDebug() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setBool('email_confirmed', true);
    await prefs.reload();

    print("🛠️ DEBUG FORCE: email_confirmed set to TRUE");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Forced verified!"), backgroundColor: Colors.green),
      );
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.email, size: 80, color: Colors.greenAccent),
                const SizedBox(height: 24),
                const Text(
                  "Check Your Email",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text(
                  "We sent a verification link.\nClick it, then tap the button below.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, color: Colors.white70),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _isChecking ? null : _checkVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 64),
                  ),
                  child: _isChecking
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text("I've Verified My Email", style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 20),

                // === DEBUG BUTTON ===
                TextButton(
                  onPressed: _forceVerifiedDebug,
                  child: const Text(
                    "DEBUG: Force Verified (Test)",
                    style: TextStyle(color: Colors.orange, fontSize: 16),
                  ),
                ),

                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Back", style: TextStyle(color: Colors.white60)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}