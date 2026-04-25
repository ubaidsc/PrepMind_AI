import 'package:freezed_annotation/freezed_annotation.dart';

part 'subject_model.freezed.dart';
part 'subject_model.g.dart';

@freezed
class Subject with _$Subject {
  const factory Subject({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    required String name,
    @JsonKey(name: 'exam_type') String? examType,
    String? semester,
    @Default('#6366F1') String color,
    @JsonKey(name: 'document_count') @Default(0) int documentCount,
    @JsonKey(name: 'ai_note_count') @Default(0) int aiNoteCount,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Subject;

  factory Subject.fromJson(Map<String, dynamic> json) =>
      _$SubjectFromJson(json);
}
