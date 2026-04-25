import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/subjects/screens/subjects_screen.dart';
import '../../features/subjects/screens/create_subject_screen.dart';
import '../../features/subjects/screens/subject_detail_screen.dart';
import '../../features/practice/screens/practice_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../shell/app_shell.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  final supabase = Supabase.instance.client;

  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final isAuth = session != null;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/signup') ||
          state.matchedLocation.startsWith('/forgot-password');

      if (!isAuth && !isAuthRoute) return '/login';
      if (isAuth && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (c, s) => const SignupScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (c, s) => const ForgotPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
          GoRoute(
            path: '/subjects',
            builder: (c, s) => const SubjectsScreen(),
            routes: [
              GoRoute(
                  path: 'create',
                  builder: (c, s) => const CreateSubjectScreen()),
              GoRoute(
                path: ':id',
                builder: (c, s) =>
                    SubjectDetailScreen(subjectId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
              path: '/practice', builder: (c, s) => const PracticeScreen()),
          GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
        ],
      ),
    ],
  );
}
