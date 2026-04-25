import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_model.freezed.dart';
part 'chat_model.g.dart';

@freezed
class ChatSession with _$ChatSession {
  const factory ChatSession({
    required String id,
    required String subjectId,
    required String userId,
    String? title,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _ChatSession;

  factory ChatSession.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionFromJson(json);
}

@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String sessionId,
    required String subjectId,
    required String userId,
    required String role,
    required String content,
    required DateTime createdAt,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}

/// Lightweight in-memory message for the chat UI (not persisted yet)
class LocalChatMessage {
  final String role;
  final String content;
  final bool isLoading;

  const LocalChatMessage({
    required this.role,
    required this.content,
    this.isLoading = false,
  });
}
