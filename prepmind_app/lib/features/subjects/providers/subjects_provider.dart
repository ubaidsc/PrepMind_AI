import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/subject_model.dart';
import '../data/subject_repository.dart';

final subjectRepositoryProvider = Provider<SubjectRepository>((ref) {
  return SubjectRepository(Supabase.instance.client);
});

final subjectsProvider = FutureProvider<List<Subject>>((ref) async {
  return ref.watch(subjectRepositoryProvider).getSubjects();
});

final subjectDetailProvider =
    FutureProvider.family<Subject, String>((ref, id) async {
  return ref.watch(subjectRepositoryProvider).getSubject(id);
});
