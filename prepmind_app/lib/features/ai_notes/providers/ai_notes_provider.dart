import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/dio_provider.dart';
import '../data/ai_note_model.dart';

final aiNotesProvider = StateNotifierProvider.family<AiNotesNotifier,
    AsyncValue<AiGeneration?>, _AiNotesKey>((ref, key) {
  return AiNotesNotifier(ref.watch(dioProvider), key);
});

typedef _AiNotesKey = ({String subjectId, String generationType});

class AiNotesNotifier extends StateNotifier<AsyncValue<AiGeneration?>> {
  final Dio _dio;
  final _AiNotesKey _key;

  AiNotesNotifier(this._dio, this._key) : super(const AsyncValue.data(null));

  Future<void> generate({
    int count = 10,
    String? query,
    bool forceRegenerate = false,
  }) async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.post('/ai/generate', data: {
        'subject_id': _key.subjectId,
        'generation_type': _key.generationType,
        'count': count,
        if (query != null) 'query': query,
        'force_regenerate': forceRegenerate,
      });
      final content = Map<String, dynamic>.from(response.data['data'] as Map);
      // Wrap into a fake AiGeneration so we can pass it around
      final generation = AiGeneration(
        id: '',
        subjectId: _key.subjectId,
        userId: '',
        generationType: _key.generationType,
        content: content,
        createdAt: DateTime.now(),
      );
      state = AsyncValue.data(generation);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final aiHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, subjectId) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/ai/history/$subjectId');
  final List data = response.data['data'] as List;
  return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});
