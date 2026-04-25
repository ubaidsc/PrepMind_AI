import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  final SupabaseClient _supabase;
  ProfileRepository(this._supabase);

  Future<Map<String, dynamic>> getProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    return data as Map<String, dynamic>;
  }

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
