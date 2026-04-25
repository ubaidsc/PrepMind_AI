import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'document_model.dart';

class DocumentRepository {
  final Dio _dio;

  DocumentRepository(this._dio);

  Future<List<DocumentModel>> getDocuments(String subjectId) async {
    final response = await _dio.get('/documents/$subjectId');
    final List data = response.data['data'] as List;
    return data
        .map((e) => DocumentModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<DocumentModel> uploadDocument(
    String subjectId,
    PlatformFile file,
  ) async {
    final bytes = file.bytes;
    if (bytes == null) throw Exception('Could not read file bytes');

    final contentType = _getContentType(file.extension ?? '');
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: file.name,
        contentType: DioMediaType.parse(contentType),
      ),
    });

    final response = await _dio.post(
      '/documents/upload/$subjectId',
      data: formData,
    );

    return DocumentModel.fromJson(
      Map<String, dynamic>.from(response.data['data'] as Map),
    );
  }

  Future<void> deleteDocument(String documentId) async {
    await _dio.delete('/documents/$documentId');
  }

  /// Poll a single document's status until it's 'ready' or 'failed'
  Future<DocumentModel> pollDocumentStatus(
    String subjectId,
    String documentId, {
    int maxAttempts = 30,
    Duration interval = const Duration(seconds: 3),
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(interval);
      final docs = await getDocuments(subjectId);
      final doc = docs.where((d) => d.id == documentId).firstOrNull;
      if (doc != null && (doc.status == 'ready' || doc.status == 'failed')) {
        return doc;
      }
    }
    throw Exception('Document processing timed out');
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }
}
