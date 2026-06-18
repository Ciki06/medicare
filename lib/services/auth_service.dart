import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import '../models/user_role.dart';

class AuthService {
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String _friendlyMessage(String code) {
    switch (code) {
      case 'CONFIGURATION_NOT_FOUND':
        return 'Email/Password sign-in is not enabled. Please contact support.';
      case 'EMAIL_EXISTS':
        return 'An account with this email already exists.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email/Password sign-in is not enabled.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Please try again later.';
      case 'EMAIL_NOT_FOUND':
        return 'No account found with this email.';
      case 'INVALID_PASSWORD':
        return 'Invalid password.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'INVALID_EMAIL':
        return 'Invalid email address.';
      case 'WEAK_PASSWORD':
        return 'Password should be at least 6 characters.';
      default:
        return code;
    }
  }

  Stream<UserModel?> get user {
    return _auth.authStateChanges().asyncMap((firebaseUser) {
      if (firebaseUser == null) return null;
      return _getUser(firebaseUser.uid);
    });
  }

  Future<UserModel?> _getUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!);
  }

  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? caregiverId,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = userCredential.user!.uid;

      final user = UserModel(
        uid: uid,
        name: name,
        email: email,
        role: role,
        createdAt: DateTime.now(),
        caregiverId: caregiverId,
        profilePicUrl: null,
        shortId: UserModel.generateId(role),
      );
      await _firestore.collection('users').doc(uid).set(user.toMap());

      return user;
    } on auth.FirebaseAuthException catch (e) {
      throw auth.FirebaseAuthException(
        code: e.code,
        message: _friendlyMessage(e.code),
      );
    }
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = userCredential.user!.uid;

      final user = await _getUser(uid);
      if (user == null) throw Exception('User data not found');
      return user;
    } on auth.FirebaseAuthException catch (e) {
      throw auth.FirebaseAuthException(
        code: e.code,
        message: _friendlyMessage(e.code),
      );
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
