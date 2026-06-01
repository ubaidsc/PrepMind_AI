import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/crypto_service.dart';

class ProfileRepository {
  final SupabaseClient _supabase;
  ProfileRepository(this._supabase);

  static const _cacheKey = 'encrypted_profile_cache';

  // ── Network fetch + write-through cache ──────────────────────────────────

  Future<Map<String, dynamic>> getProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final data =
        await _supabase.from('profiles').select().eq('id', userId).single();
    // Encrypt and persist the freshly fetched PII
    await _saveToCache(data);
    return data;
  }

  // ── Encrypted local cache ─────────────────────────────────────────────────

  /// Returns the last known profile from the encrypted local cache, or null
  /// if no cache exists yet.
  Future<Map<String, dynamic>?> getCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cipherText = prefs.getString(_cacheKey);
      if (cipherText == null) return null;
      final jsonString = CryptoService.decrypt(cipherText);
      return Map<String, dynamic>.from(jsonDecode(jsonString) as Map);
    } catch (_) {
      // Corrupted or tampered cache — discard it silently
      await clearCache();
      return null;
    }
  }

  Future<void> _saveToCache(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(profile);
    final cipherText = CryptoService.encrypt(jsonString);
    await prefs.setString(_cacheKey, cipherText);
  }

  /// Removes the cached profile (e.g. on sign-out).
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  // ── Profile update ────────────────────────────────────────────────────────

  Future<void> updateProfile({String? fullName, String? avatarUrl}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (updates.isEmpty) return;
    await _supabase.from('profiles').update(updates).eq('id', userId);
  }
}
