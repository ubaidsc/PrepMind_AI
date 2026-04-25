import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/subjects_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../documents/providers/documents_provider.dart';
import '../../documents/screens/upload_document_screen.dart';
import '../../ai_notes/screens/generate_options_screen.dart';
import '../../chat/screens/chat_screen.dart';

class SubjectDetailScreen extends ConsumerStatefulWidget {
  final String subjectId;
  const SubjectDetailScreen({super.key, required this.subjectId});

  @override
  ConsumerState<SubjectDetailScreen> createState() =>
      _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends ConsumerState<SubjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subjectAsync = ref.watch(subjectDetailProvider(widget.subjectId));

    return subjectAsync.when(
      data: (subject) {
        final color = Color(int.parse(subject.color.replaceAll('#', '0xFF')));
        return Scaffold(
          backgroundColor: Colors.white,
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 160,
                pinned: true,
                backgroundColor: color,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 56, bottom: 60),
                  title: Text(
                    subject.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  background: Container(color: color),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    onPressed: () => _confirmDelete(context),
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  tabs: const [
                    Tab(text: 'Documents'),
                    Tab(text: 'AI Notes'),
                    Tab(text: 'AI Chat'),
                  ],
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Documents
                UploadDocumentScreen(subjectId: widget.subjectId),
                // Tab 2: AI Notes
                _AiNotesTab(subjectId: widget.subjectId),
                // Tab 3: AI Chat
                ChatScreen(
                  subjectId: widget.subjectId,
                  subjectName: subject.name,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Subject'),
        content: const Text(
            'This will delete the subject and all its documents. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(subjectRepositoryProvider).deleteSubject(widget.subjectId);
      ref.invalidate(subjectsProvider);
      if (mounted && context.mounted) context.go('/subjects');
    }
  }
}

// ─── AI Notes Tab ─────────────────────────────────────────────────────────────

class _AiNotesTab extends ConsumerWidget {
  final String subjectId;
  const _AiNotesTab({required this.subjectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsProvider(subjectId));

    return docsAsync.when(
      data: (docs) {
        final hasReadyDocs = docs.any((d) => d.status == 'ready');
        if (!hasReadyDocs) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.upload_file_outlined,
                      size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  const Text(
                    'No processed documents yet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Upload documents in the Documents tab and wait for processing to complete.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }
        return GenerateOptionsScreen(subjectId: subjectId);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
