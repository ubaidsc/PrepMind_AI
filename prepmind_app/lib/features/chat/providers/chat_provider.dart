import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/dio_provider.dart';
import '../data/chat_model.dart';

// ─── Chat State ───────────────────────────────────────────────────────────────

class ChatState {
  final List<LocalChatMessage> messages;
  final String? sessionId;
  final bool isSending;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.sessionId,
    this.isSending = false,
    this.error,
  });

  ChatState copyWith({
    List<LocalChatMessage>? messages,
    String? sessionId,
    bool? isSending,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      sessionId: sessionId ?? this.sessionId,
      isSending: isSending ?? this.isSending,
      error: error,
    );
  }
}

// ─── Chat Notifier ────────────────────────────────────────────────────────────

class ChatNotifier extends StateNotifier<ChatState> {
  final Dio _dio;
  final String _subjectId;

  ChatNotifier(this._dio, this._subjectId) : super(const ChatState());

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty || state.isSending) return;

    // Optimistically append user message
    final userMsg = LocalChatMessage(role: 'user', content: message.trim());
    final typingMsg =
        const LocalChatMessage(role: 'assistant', content: '', isLoading: true);

    state = state.copyWith(
      messages: [...state.messages, userMsg, typingMsg],
      isSending: true,
      error: null,
    );

    try {
      final response = await _dio.post('/chat/message', data: {
        'subject_id': _subjectId,
        'message': message.trim(),
        if (state.sessionId != null) 'session_id': state.sessionId,
      });

      final data = Map<String, dynamic>.from(response.data['data'] as Map);
      final assistantMsg = LocalChatMessage(
        role: 'assistant',
        content: data['message']?.toString() ?? '',
      );

      // Replace typing indicator with actual response
      final updatedMessages = [...state.messages];
      updatedMessages.removeLast();
      updatedMessages.add(assistantMsg);

      state = state.copyWith(
        messages: updatedMessages,
        sessionId: data['session_id']?.toString() ?? state.sessionId,
        isSending: false,
      );
    } on DioException catch (e) {
      final updatedMessages = [...state.messages];
      updatedMessages.removeLast(); // remove typing indicator
      final errMsg = e.response?.data?['detail']?.toString() ??
          'Failed to get response. Check your connection.';
      state = state.copyWith(
        messages: updatedMessages,
        isSending: false,
        error: errMsg,
      );
    }
  }

  Future<void> loadSession(String sessionId) async {
    try {
      final response = await _dio.get('/chat/messages/$sessionId');
      final List data = response.data['data'] as List;
      final messages = data.map((m) {
        final msg = Map<String, dynamic>.from(m as Map);
        return LocalChatMessage(
          role: msg['role']?.toString() ?? 'user',
          content: msg['content']?.toString() ?? '',
        );
      }).toList();
      state = state.copyWith(messages: messages, sessionId: sessionId);
    } catch (_) {}
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// ─── Providers ───────────────────────────────────────────────────────────────

final chatProvider =
    StateNotifierProvider.family<ChatNotifier, ChatState, String>(
        (ref, subjectId) {
  return ChatNotifier(ref.watch(dioProvider), subjectId);
});

final chatSessionsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, subjectId) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/chat/sessions/$subjectId');
  final List data = response.data['data'] as List;
  return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});
