class ConversationItem {
  final String id;
  final String title;
  final String preview;
  final int stepCount;
  final String status;
  final String lastModified;
  final bool hasUnread;
  final bool isActive;

  ConversationItem({
    required this.id,
    required this.title,
    this.preview = '',
    this.stepCount = 0,
    this.status = 'done',
    this.lastModified = '',
    this.hasUnread = false,
    this.isActive = false,
  });

  factory ConversationItem.fromJson(Map<String, dynamic> json) {
    return ConversationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Conversation',
      preview: json['preview']?.toString() ?? '',
      stepCount: (json['step_count'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'done',
      lastModified: json['last_modified']?.toString() ?? '',
      hasUnread: json['has_unread'] == true,
      isActive: json['is_active'] == true,
    );
  }
}

class ProjectGroup {
  final String name;
  final String path;
  bool isExpanded;
  final int totalConversations;
  final List<ConversationItem> conversations;

  ProjectGroup({
    required this.name,
    this.path = '',
    this.isExpanded = false,
    this.totalConversations = 0,
    required this.conversations,
  });

  factory ProjectGroup.fromJson(Map<String, dynamic> json) {
    final rawConvos = json['conversations'] as List<dynamic>? ?? [];
    return ProjectGroup(
      name: json['name'] as String? ?? 'Project',
      path: json['path'] as String? ?? '',
      isExpanded: json['is_expanded'] as bool? ?? false,
      totalConversations: json['total_conversations'] as int? ?? rawConvos.length,
      conversations: rawConvos.map((e) => ConversationItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
