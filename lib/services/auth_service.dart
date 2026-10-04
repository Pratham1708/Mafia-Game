import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  String? _cachedUid;
  String? _displayName;
  bool _isFirebaseAvailable = false;

  String? get currentUid => _cachedUid;
  String? get displayName => _displayName;
  bool get isFirebaseAvailable => _isFirebaseAvailable;

  void setDisplayName(String name) {
    _displayName = validateDisplayName(name);
  }

  /// Validates display name:
  /// - 2–20 characters
  /// - Trim whitespace
  /// - Reject empty names
  static String? validateDisplayName(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.length < 2 || trimmed.length > 20) {
      return null;
    }
    return trimmed;
  }

  /// Initializes anonymous authentication.
  Future<String> initializeAuth() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null) {
        _cachedUid = auth.currentUser!.uid;
        _isFirebaseAvailable = true;
        debugPrint('Resumed existing Firebase Auth session. UID: $_cachedUid');
        return _cachedUid!;
      }
      final userCredential = await auth.signInAnonymously();
      _cachedUid = userCredential.user?.uid;
      _isFirebaseAvailable = true;
      debugPrint('Authenticated via Firebase Auth. UID: $_cachedUid');
      return _cachedUid!;
    } catch (e) {
      debugPrint('Firebase Auth not available ($e).');
      _isFirebaseAvailable = false;
      _cachedUid ??= 'local_${Random().nextInt(999999).toString().padLeft(6, '0')}';
      return _cachedUid!;
    }
  }

  /// Attempts to re-establish connection and authentication.
  Future<bool> reconnect() async {
    try {
      await initializeAuth();
      return _isFirebaseAvailable;
    } catch (_) {
      return false;
    }
  }

  /// Sets custom fallback UID (e.g. for testing)
  void setCustomUid(String uid) {
    _cachedUid = uid;
  }
}
