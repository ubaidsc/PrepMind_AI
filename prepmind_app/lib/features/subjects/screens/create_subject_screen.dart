import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/subjects_provider.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/validators.dart';

class CreateSubjectScreen extends ConsumerStatefulWidget {
  const CreateSubjectScreen({super.key});

  @override
  ConsumerState<CreateSubjectScreen> createState() =>
      _CreateSubjectScreenState();
}

class _CreateSubjectScreenState extends ConsumerState<CreateSubjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _examTypeController = TextEditingController();
  final _semesterController = TextEditingController();
  String _selectedColor = '#6366F1';
  bool _isLoading = false;

  static const _colorOptions = [
    '#3B82F6',
    '#8B5CF6',
    '#10B981',
    '#F97316',
    '#EF4444',
    '#6366F1',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _examTypeController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(subjectRepositoryProvider).createSubject(
            name: _nameController.text.trim(),
            examType: _examTypeController.text.trim().isEmpty
                ? null
                : _examTypeController.text.trim(),
            semester: _semesterController.text.trim().isEmpty
                ? null
                : _semesterController.text.trim(),
            color: _selectedColor,
          );
      ref.invalidate(subjectsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'New Subject',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                label: 'Subject Name',
                hint: 'e.g. Advanced Mathematics',
                controller: _nameController,
                validator: (v) => Validators.required(v, field: 'Subject name'),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Exam Type (optional)',
                hint: 'e.g. Midterm, Final, GCSE',
                controller: _examTypeController,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Semester (optional)',
                hint: 'e.g. Fall 2025',
                controller: _semesterController,
              ),
              const SizedBox(height: 24),
              const Text(
                'Color',
                style:
                    TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: _colorOptions.map((color) {
                  final c = Color(
                      int.parse(color.replaceAll('#', '0xFF')));
                  final isSelected = _selectedColor == color;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Colors.black,
                                width: 3,
                              )
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 40),
              AppButton(
                label: 'Create Subject',
                onPressed: _create,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
