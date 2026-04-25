import 'package:supabase_flutter/supabase_flutter.dart';
import 'subject_model.dart';

class SubjectRepository {
  final SupabaseClient _supabase;
  SubjectRepository(this._supabase);

  Future<List<Subject>> getSubjects() async {
    final data = await _supabase
        .from('subjects')
        .select()
        .order('updated_at', ascending: false);
    return (data as List)
        .map((e) => Subject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Subject> createSubject({
    required String name,
    String? examType,
    String? semester,
    String color = '#6366F1',
  }) async {
    final data = await _supabase
        .from('subjects')
        .insert({
          'name': name,
          'exam_type': examType,
          'semester': semester,
          'color': color,
          'user_id': _supabase.auth.currentUser!.id,
        })
        .select()
        .single();
    return Subject.fromJson(data);
  }

  Future<Subject> getSubject(String id) async {
    final data =
        await _supabase.from('subjects').select().eq('id', id).single();
    return Subject.fromJson(data);
  }

  Future<void> deleteSubject(String id) async {
    await _supabase.from('subjects').delete().eq('id', id);
  }
}
