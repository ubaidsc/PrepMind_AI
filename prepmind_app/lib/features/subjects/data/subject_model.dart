import 'package:freezed_annotation/freezed_annotation.dart';

part 'subject_model.freezed.dart';
part 'subject_model.g.dart';

@freezed
class Subject with _$Subject {
  const factory Subject({
    required String id,
    required String userId,
    required String name,
    String? examType,
    String? semester,
    @Default('#6366F1') String color,
    @Default(0) int documentCount,
    @Default(0) int aiNoteCount,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Subject;

  factory Subject.fromJson(Map<String, dynamic> json) =>
      _$SubjectFromJson(json);
}
