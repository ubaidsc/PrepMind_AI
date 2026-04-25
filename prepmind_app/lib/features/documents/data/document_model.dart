import 'package:freezed_annotation/freezed_annotation.dart';

part 'document_model.freezed.dart';
part 'document_model.g.dart';

@freezed
class DocumentModel with _$DocumentModel {
  const factory DocumentModel({
    required String id,
    required String subjectId,
    required String userId,
    required String name,
    required String fileType,
    required int fileSizeBytes,
    required String storagePath,
    @Default('uploaded') String status,
    int? pageCount,
    String? errorMessage,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _DocumentModel;

  factory DocumentModel.fromJson(Map<String, dynamic> json) =>
      _$DocumentModelFromJson(json);
}
