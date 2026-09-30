class SkillModel {
  final String id;
  final String name;
  final String description;
  final String source;
  final String path;
  final bool isEnabled;
  final bool isEditable;
  final String instructionPreview;
  final String? fullInstructions;

  SkillModel({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    required this.path,
    required this.isEnabled,
    this.isEditable = false,
    required this.instructionPreview,
    this.fullInstructions,
  });

  factory SkillModel.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as String? ?? 'global';
    return SkillModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      source: source,
      path: json['path'] as String? ?? '',
      isEnabled: json['is_enabled'] as bool? ?? true,
      isEditable: json['is_editable'] as bool? ?? (source != 'builtin'),
      instructionPreview: json['instruction_preview'] as String? ?? '',
      fullInstructions: json['full_instructions'] as String?,
    );
  }
}
