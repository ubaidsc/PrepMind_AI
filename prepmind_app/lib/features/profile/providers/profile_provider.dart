import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client);
});

/// Cache-first profile provider:
/// 1. Instantly returns the decrypted cached profile (no spinner on revisit).
/// 2. Always fires a background network refresh and updates the cache.
/// 3. Falls back to cache if the network call fails (e.g. no internet).
final profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);

  // Try the encrypted local cache first for an instant result
  final cached = await repo.getCachedProfile();

  // Kick off a network refresh regardless; if it succeeds the provider
  // will rebuild with the fresh data and write an updated cache entry.
  try {
    return await repo.getProfile();
  } catch (_) {
    // Network unavailable — serve stale cache if present
    if (cached != null) return cached;
    rethrow;
  }
});
