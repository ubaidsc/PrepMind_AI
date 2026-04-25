import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class GenerateOptionsScreen extends StatelessWidget {
  final String subjectId;
  const GenerateOptionsScreen({super.key, required this.subjectId});

  static const _options = [
    _GenOption(
        'Summary', 'summary', Icons.summarize_outlined, Color(0xFF6366F1)),
    _GenOption(
        'Key Points', 'key_points', Icons.lightbulb_outline, Color(0xFFF59E0B)),
    _GenOption('MCQs', 'mcq', Icons.quiz_outlined, Color(0xFF10B981)),
    _GenOption(
        'Flashcards', 'flashcards', Icons.style_outlined, Color(0xFF3B82F6)),
    _GenOption('5-Mark Q&A', 'five_mark_qa', Icons.edit_note_outlined,
        Color(0xFF8B5CF6)),
    _GenOption('10-Mark Q&A', 'ten_mark_qa', Icons.article_outlined,
        Color(0xFFEF4444)),
    _GenOption('Revision Sheet', 'revision_sheet', Icons.checklist_outlined,
        Color(0xFF06B6D4)),
    _GenOption(
        'Mind Map', 'mind_map', Icons.account_tree_outlined, Color(0xFFF97316)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Generate AI Notes',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose what to generate from your documents:',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: _options.length,
                itemBuilder: (context, i) => _GenCard(
                  option: _options[i],
                  onTap: () => context.push(
                    '/subjects/$subjectId/result',
                    extra: {
                      'type': _options[i].type,
                      'label': _options[i].label,
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenOption {
  final String label;
  final String type;
  final IconData icon;
  final Color color;
  const _GenOption(this.label, this.type, this.icon, this.color);
}

class _GenCard extends StatelessWidget {
  final _GenOption option;
  final VoidCallback onTap;

  const _GenCard({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: option.color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: option.color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: option.color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(option.icon, color: option.color, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              option.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: option.color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
