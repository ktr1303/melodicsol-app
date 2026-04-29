import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Keys for SharedPreferences
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyUserEmail = 'user_email';
  static const String _keyEmailConfirmed = 'email_confirmed';

  // Current user state
  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  // Stream for auth changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Save login state locally
  Future<void> _saveLoginState(String email, bool isConfirmed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserEmail, email);
    await prefs.setBool(_keyEmailConfirmed, isConfirmed);
  }

  // Load login state
  Future<Map<String, dynamic>> loadLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isLoggedIn': prefs.getBool(_keyIsLoggedIn) ?? false,
      'email': prefs.getString(_keyUserEmail) ?? '',
      'emailConfirmed': prefs.getBool(_keyEmailConfirmed) ?? false,
    };
  }

  // Clear login state (for logout)
  Future<void> clearLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyEmailConfirmed);
  }

  // Sign up with email + password
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      final UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _saveLoginState(email, false); // Not confirmed yet
      return cred.user;
    } catch (e) {
      rethrow;
    }
  }

  // Login with email + password
  Future<User?> loginWithEmail(String email, String password) async {
    try {
      final UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _saveLoginState(email, cred.user?.emailVerified ?? false);
      return cred.user;
    } catch (e) {
      rethrow;
    }
  }

  // Send email verification
  Future<void> sendVerificationEmail() async {
    if (_auth.currentUser != null && !_auth.currentUser!.emailVerified) {
      await _auth.currentUser!.sendEmailVerification();
    }
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
    await clearLoginState();
  }

  // Check if email is verified (refresh)
  Future<bool> checkEmailVerification() async {
    if (_auth.currentUser == null) return false;
    await _auth.currentUser!.reload();
    final verified = _auth.currentUser!.emailVerified;
    if (verified) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEmailConfirmed, true);
    }
    return verified;
  }
}