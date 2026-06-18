import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/profile_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subjects/providers/subjects_provider.dart';
import '../../../core/constants/app_colors.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: profileAsync.when(
        data: (profile) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(profileProvider),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.primaryLight,
                      child: Text(
                        (profile['full_name'] as String? ?? user?.email ?? 'U')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile['full_name'] as String? ?? 'No name',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        (profile['plan'] as String? ?? 'free').toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Usage',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _UsageCard(
                label: 'AI Requests',
                used: profile['ai_requests_used'] as int? ?? 0,
                limit: profile['ai_requests_limit'] as int? ?? 20,
                icon: Icons.psychology_outlined,
              ),
              const SizedBox(height: 12),
              _UsageCard(
                label: 'Documents',
                used: profile['documents_uploaded'] as int? ?? 0,
                limit: profile['documents_limit'] as int? ?? 5,
                icon: Icons.description_outlined,
              ),
              const SizedBox(height: 32),
              const Divider(),
              ListTile(
                leading:
                    const Icon(Icons.bug_report_outlined, color: Colors.orange),
                title: const Text('Test Crash Report',
                    style: TextStyle(color: Colors.orange)),
                onTap: () async {
                  await FirebaseAnalytics.instance
                      .logEvent(name: 'test_crash_triggered');
                  FirebaseCrashlytics.instance.crash();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: const Text('Sign Out',
                    style: TextStyle(color: AppColors.error)),
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading profile: $e')),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Clear encrypted profile cache before signing out so the next user
      // on this device cannot access the previous user's locally cached PII.
      await ref.read(profileRepositoryProvider).clearCache();
      ref.invalidate(profileProvider); // Clear Riverpod memory cache
      ref.invalidate(subjectsProvider); // Clear subjects memory cache
      await ref.read(authRepositoryProvider).signOut();
      if (context.mounted) context.go('/login');
    }
  }
}

class _UsageCard extends StatelessWidget {
  final String label;
  final int used;
  final int limit;
  final IconData icon;

  const _UsageCard({
    required this.label,
    required this.used,
    required this.limit,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final progress = limit > 0 ? used / limit : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('$used / $limit',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade200,
                  color: progress >= 0.9 ? AppColors.error : AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
