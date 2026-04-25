import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client);
});

final profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(profileRepositoryProvider).getProfile();
});
