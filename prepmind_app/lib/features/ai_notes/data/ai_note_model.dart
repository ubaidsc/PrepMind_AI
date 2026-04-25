import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_note_model.freezed.dart';
part 'ai_note_model.g.dart';

@freezed
class AiGeneration with _$AiGeneration {
  const factory AiGeneration({
    required String id,
    required String subjectId,
    required String userId,
    required String generationType,
    required Map<String, dynamic> content,
    @Default([]) List<String> documentIds,
    @Default(0) int promptTokens,
    @Default(0) int completionTokens,
    @Default('gemini-2.5-flash') String modelUsed,
    required DateTime createdAt,
  }) = _AiGeneration;

  factory AiGeneration.fromJson(Map<String, dynamic> json) =>
      _$AiGenerationFromJson(json);
}
