import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  final SupabaseClient _supabase;
  AuthRepository(this._supabase);

  User? get currentUser => _supabase.auth.currentUser;
  Session? get currentSession => _supabase.auth.currentSession;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signInWithGoogle() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.prepmind://login-callback',
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
