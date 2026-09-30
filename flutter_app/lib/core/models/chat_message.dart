enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final int accountId;
  String text;
  String thinking;
  List<Map<String, dynamic>> toolCalls;
  List<Map<String, dynamic>> attachments;
  bool isStreaming;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.accountId,
    this.text = '',
    this.thinking = '',
    List<Map<String, dynamic>>? toolCalls,
    List<Map<String, dynamic>>? attachments,
    this.isStreaming = false,
    DateTime? timestamp,
  })  : toolCalls = toolCalls ?? [],
        attachments = attachments ?? [],
        timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    int? accountId,
    String? text,
    String? thinking,
    List<Map<String, dynamic>>? toolCalls,
    List<Map<String, dynamic>>? attachments,
    bool? isStreaming,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      accountId: accountId ?? this.accountId,
      text: text ?? this.text,
      thinking: thinking ?? this.thinking,
      toolCalls: toolCalls ?? List.from(this.toolCalls),
      attachments: attachments ?? List.from(this.attachments),
      isStreaming: isStreaming ?? this.isStreaming,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
