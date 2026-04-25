import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_model.freezed.dart';
part 'chat_model.g.dart';

@freezed
class ChatSession with _$ChatSession {
  const factory ChatSession({
    required String id,
    @JsonKey(name: 'subject_id') required String subjectId,
    @JsonKey(name: 'user_id') required String userId,
    String? title,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _ChatSession;

  factory ChatSession.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionFromJson(json);
}

@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    @JsonKey(name: 'session_id') required String sessionId,
    @JsonKey(name: 'subject_id') required String subjectId,
    @JsonKey(name: 'user_id') required String userId,
    required String role,
    required String content,
    @JsonKey(name: 'created_at') required DateTime createdAt,
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
