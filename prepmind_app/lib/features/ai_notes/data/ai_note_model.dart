import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_note_model.freezed.dart';
part 'ai_note_model.g.dart';

@freezed
class AiGeneration with _$AiGeneration {
  const factory AiGeneration({
    required String id,
    @JsonKey(name: 'subject_id') required String subjectId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'generation_type') required String generationType,
    required Map<String, dynamic> content,
    @JsonKey(name: 'document_ids') @Default([]) List<String> documentIds,
    @JsonKey(name: 'prompt_tokens') @Default(0) int promptTokens,
    @JsonKey(name: 'completion_tokens') @Default(0) int completionTokens,
    @JsonKey(name: 'model_used') @Default('gemini-2.5-flash') String modelUsed,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _AiGeneration;

  factory AiGeneration.fromJson(Map<String, dynamic> json) =>
      _$AiGenerationFromJson(json);
}
