import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/subjects_provider.dart';
import '../../../shared/widgets/subject_card.dart';
import '../../../core/constants/app_colors.dart';

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(subjectsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'My Subjects',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/subjects/create'),
          ),
        ],
      ),
      body: subjectsAsync.when(
        data: (subjects) => subjects.isEmpty
            ? _EmptyState(onAdd: () => context.push('/subjects/create'))
            : GridView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: subjects.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (ctx, i) => SubjectCard(
                  subject: subjects[i],
                  onTap: () => context.push('/subjects/${subjects[i].id}'),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _EmptyState(onAdd: () => context.push('/subjects/create')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/subjects/create'),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.menu_book_outlined,
              size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          const Text(
            'No subjects yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your first subject to get started',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Subject'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
