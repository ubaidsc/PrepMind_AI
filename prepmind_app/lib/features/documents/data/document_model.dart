import 'package:freezed_annotation/freezed_annotation.dart';

part 'document_model.freezed.dart';
part 'document_model.g.dart';

@freezed
class DocumentModel with _$DocumentModel {
  const factory DocumentModel({
    required String id,
    @JsonKey(name: 'subject_id') required String subjectId,
    @JsonKey(name: 'user_id') required String userId,
    required String name,
    @JsonKey(name: 'file_type') required String fileType,
    @JsonKey(name: 'file_size_bytes') required int fileSizeBytes,
    @JsonKey(name: 'storage_path') required String storagePath,
    @Default('uploaded') String status,
    @JsonKey(name: 'page_count') int? pageCount,
    @JsonKey(name: 'error_message') String? errorMessage,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _DocumentModel;

  factory DocumentModel.fromJson(Map<String, dynamic> json) =>
      _$DocumentModelFromJson(json);
}
