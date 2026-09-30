class WorkspaceNode {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final List<WorkspaceNode> children;

  WorkspaceNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    List<WorkspaceNode>? children,
  }) : children = children ?? [];

  factory WorkspaceNode.fromJson(Map<String, dynamic> json) {
    var rawChildren = json['children'] as List<dynamic>?;
    List<WorkspaceNode> parsedChildren = [];
    if (rawChildren != null) {
      parsedChildren = rawChildren
          .map((c) => WorkspaceNode.fromJson(c as Map<String, dynamic>))
          .toList();
    }
    return WorkspaceNode(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDirectory: json['is_directory'] as bool? ?? false,
      size: json['size'] as int?,
      children: parsedChildren,
    );
  }
}
