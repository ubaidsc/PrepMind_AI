import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/dio_provider.dart';
import '../data/document_model.dart';
import '../data/document_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(ref.watch(dioProvider));
});

final documentsProvider =
    FutureProvider.family<List<DocumentModel>, String>((ref, subjectId) async {
  return ref.watch(documentRepositoryProvider).getDocuments(subjectId);
});
