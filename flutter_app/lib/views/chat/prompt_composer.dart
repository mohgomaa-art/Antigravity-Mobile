import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api/agy_client.dart';
import '../../core/theme/agy_theme.dart';

class ComposerAttachment {
  final String name;
  final String? path;
  final Uint8List bytes;
  final bool isImage;
  final int size;

  ComposerAttachment({
    required this.name,
    this.path,
    required this.bytes,
    required this.isImage,
    required this.size,
  });
}


class AgyModelVariant {
  final String id;
  final String title;
  final String? tier;
  final String? protoEnum;

  const AgyModelVariant({
    required this.id,
    required this.title,
    this.tier,
    this.protoEnum,
  });

  factory AgyModelVariant.fromJson(Map<String, dynamic> json) {
    return AgyModelVariant(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      tier: json['tier'] as String?,
      protoEnum: json['proto_enum'] as String?,
    );
  }
}

class AgyModelItem {
  final String id;
  final String title;
  final String? tier;
  final bool isFast;
  final bool hasArrow;
  final String displayName;
  final String? protoEnum;
  final String? cliTier;
  final bool isDefault;
  final List<AgyModelVariant> variants;

  const AgyModelItem({
    this.id = '',
    required this.title,
    this.tier,
    this.isFast = false,
    this.hasArrow = false,
    String? displayName,
    this.protoEnum,
    this.cliTier,
    this.isDefault = false,
    this.variants = const [],
  }) : displayName = displayName ?? (tier != null ? '$title $tier' : title);

  factory AgyModelItem.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String? ?? 'Model';
    final tier = json['tier'] as String?;
    final rawDisplayName = json['display_name'] as String?;
    final rawVariants = json['variants'] as List?;
    final variants = rawVariants != null
        ? rawVariants
            .whereType<Map<String, dynamic>>()
            .map((v) => AgyModelVariant.fromJson(v))
            .toList()
        : <AgyModelVariant>[];

    return AgyModelItem(
      id: json['id'] as String? ?? '',
      title: title,
      tier: tier,
      isFast: json['is_fast'] as bool? ?? false,
      hasArrow: json['has_arrow'] as bool? ?? false,
      displayName: rawDisplayName ?? (tier != null ? '$title $tier' : title),
      protoEnum: json['proto_enum'] as String?,
      cliTier: json['cli_tier'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
      variants: variants,
    );
  }
}

const List<AgyModelItem> kDefaultAgyModels = [
  AgyModelItem(id: 'gemini-3.8-flash', title: 'Gemini 3.8 Flash', tier: 'High'),
  AgyModelItem(id: 'gemini-3.7-flash', title: 'Gemini 3.7 Flash', tier: 'Medium', hasArrow: true),
  AgyModelItem(id: 'gemini-3.6-flash', title: 'Gemini 3.6 Flash', tier: 'Medium', isFast: true, hasArrow: true),
  AgyModelItem(id: 'gemini-3.1-pro', title: 'Gemini 3.1 Pro', tier: 'Low', hasArrow: true),
  AgyModelItem(id: 'claude-sonnet-4.6-thinking', title: 'Claude Sonnet 4.6 (Thinking)'),
  AgyModelItem(id: 'claude-opus-4.6-thinking', title: 'Claude Opus 4.6 (Thinking)'),
  AgyModelItem(id: 'gpt-oss-120b-medium', title: 'GPT-OSS 120B (Medium)'),
];

const List<AgyModelItem> realAgyModels = kDefaultAgyModels;

const List<Map<String, dynamic>> kDefaultCommands = [
  {
    'command': '/plan',
    'name': 'Plan',
    'description': 'Formulate a multi-phase architectural plan before modifying code',
    'category': 'workflow',
    'icon': 'assignment_outlined',
    'badge': 'PLAN',
  },
  {
    'command': '/btw',
    'name': 'By The Way',
    'description': 'Quick side question without disrupting ongoing project context',
    'category': 'utility',
    'icon': 'chat_bubble_outline',
    'badge': 'BTW',
  },
  {
    'command': '/browser',
    'name': 'Browser',
    'description': 'Web research, URL content extraction, and browser automation',
    'category': 'automation',
    'icon': 'language',
    'badge': 'BROWSER',
  },
  {
    'command': '/goal',
    'name': 'Goal',
    'description': 'Autonomous execution loop until the objective is completely verified',
    'category': 'workflow',
    'icon': 'flag_outlined',
    'badge': 'GOAL',
  },
  {
    'command': '/schedule',
    'name': 'Schedule',
    'description': 'Set a one-time timer or recurring cron automation task',
    'category': 'automation',
    'icon': 'schedule',
    'badge': 'CRON',
  },
  {
    'command': '/grill-me',
    'name': 'Grill Me',
    'description': 'Interactive design review interview to resolve trade-offs before building',
    'category': 'workflow',
    'icon': 'psychology_outlined',
    'badge': 'INTERVIEW',
  },
  {
    'command': '/boost',
    'name': 'Boost',
    'description': 'Maximum cognitive depth, multi-perspective analysis, and verification',
    'category': 'reasoning',
    'icon': 'bolt',
    'badge': 'BOOST',
  },
  {
    'command': '/learn',
    'name': 'Learn',
    'description': 'Persist user preference or correction into project rules for all future turns',
    'category': 'memory',
    'icon': 'school_outlined',
    'badge': 'LEARN',
  },
  {
    'command': '/clear',
    'name': 'Clear Chat',
    'description': 'Reset active canvas and start a fresh Antigravity conversation',
    'category': 'client',
    'icon': 'delete_outline',
    'badge': 'CLEAR',
  },
  {
    'command': '/help',
    'name': 'Help & Guide',
    'description': 'View guide on slash commands, skills, and autonomous workflows',
    'category': 'client',
    'icon': 'help_outline',
    'badge': 'HELP',
  },
];

IconData getCommandIcon(String cmd) {
  switch (cmd) {
    case '/plan':
      return Icons.assignment_outlined;
    case '/btw':
      return Icons.chat_bubble_outline;
    case '/browser':
      return Icons.language;
    case '/goal':
      return Icons.flag_outlined;
    case '/schedule':
      return Icons.schedule;
    case '/grill-me':
      return Icons.psychology_outlined;
    case '/boost':
      return Icons.bolt;
    case '/learn':
      return Icons.school_outlined;
    case '/clear':
    case '/reset':
      return Icons.delete_outline;
    case '/help':
      return Icons.help_outline;
    default:
      return Icons.terminal_rounded;
  }
}

class PromptComposer extends StatefulWidget {
  final int activeAccountId;
  final AgyClient? client;
  final Function(String text, String model, {List<Map<String, dynamic>>? attachments}) onSend;
  final bool isStreaming;
  final VoidCallback? onStop;
  final Function(String text)? onSteer;
  final Function(String text, String model)? onQueue;
  final int queuedCount;
  final VoidCallback? onClear;
  final VoidCallback? onFocus;
  final ValueChanged<String>? onModelChanged;

  const PromptComposer({
    super.key,
    required this.activeAccountId,
    this.client,
    required this.onSend,
    this.isStreaming = false,
    this.onStop,
    this.onSteer,
    this.onQueue,
    this.queuedCount = 0,
    this.onClear,
    this.onFocus,
    this.onModelChanged,
  });

  @override
  State<PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends State<PromptComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _selectedModel = 'Gemini 3.8 Flash High';
  final List<ComposerAttachment> _attachments = [];
  bool _isUploading = false;
  List<Map<String, dynamic>> _matchingFiles = [];
  bool _isLoadingFiles = false;
  Timer? _fileSearchDebounce;
  List<Map<String, dynamic>> _commandsList = List.from(kDefaultCommands);
  List<AgyModelItem> _modelsList = List.from(kDefaultAgyModels);
  Map<String, dynamic>? _cachedQuota;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _fetchCommands();
    _fetchModels();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      widget.onFocus?.call();
    }
  }

  Future<void> _fetchModels() async {
    try {
      final client = AgyClient();
      final dynamicModels = await client.getModels();
      final quota = await client.getQuotaSummary();
      if (mounted) {
        setState(() {
          if (dynamicModels.isNotEmpty) {
            final parsed = dynamicModels.map((m) => AgyModelItem.fromJson(m)).toList();
            _modelsList = parsed;
            final exists = parsed.any((m) =>
                m.displayName == _selectedModel ||
                m.title == _selectedModel ||
                _selectedModel.startsWith(m.title));
            if (!exists) {
              final defaultModel = parsed.firstWhere((m) => m.isDefault, orElse: () => parsed.first);
              _selectedModel = defaultModel.displayName;
            }
          }
          if (quota != null) {
            _cachedQuota = quota;
          }
        });
      }
    } catch (_) {}
  }

  String _getQuickQuotaPreview() {
    if (_cachedQuota == null) return '';
    try {
      final groups = _cachedQuota!['groups'] as List?;
      if (groups != null && groups.isNotEmpty) {
        final g = groups[0] as Map<String, dynamic>;
        final buckets = g['buckets'] as List?;
        if (buckets != null && buckets.isNotEmpty) {
          final b = buckets.firstWhere(
            (item) => item['window'] == '5h',
            orElse: () => buckets[0],
          );
          final frac = (b['remainingFraction'] as num?)?.toDouble() ?? 1.0;
          final pct = (frac * 100).clamp(0, 100).toInt();
          return '$pct% remaining';
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> _fetchCommands() async {
    try {
      final dynamicCmds = await AgyClient().getCommands();
      if (mounted && dynamicCmds.isNotEmpty) {
        final existing = kDefaultCommands.map((c) => c['command'] as String).toSet();
        final combined = List<Map<String, dynamic>>.from(kDefaultCommands);
        for (final c in dynamicCmds) {
          final cmdStr = c['command'] as String? ?? '';
          if (!existing.contains(cmdStr)) {
            combined.add({
              'command': cmdStr,
              'name': c['name'] ?? cmdStr,
              'description': c['description'] ?? 'Antigravity skill',
              'category': c['category'] ?? 'skills',
              'icon': c['icon'] ?? 'extension_outlined',
              'badge': 'SKILL',
            });
          }
        }
        setState(() {
          _commandsList = combined;
        });
      }
    } catch (_) {}
  }

  String? _getAtMentionQuery() {
    final text = _controller.text;
    final sel = _controller.selection;
    if (sel.baseOffset <= 0 || sel.baseOffset > text.length) return null;
    final beforeCursor = text.substring(0, sel.baseOffset);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex == -1) return null;
    if (atIndex > 0 && !RegExp(r'[\s\(\[\{]').hasMatch(beforeCursor[atIndex - 1])) {
      return null;
    }
    final query = beforeCursor.substring(atIndex + 1);
    if (query.contains(' ') || query.contains('\n') || query.contains(']')) return null;
    return query;
  }

  void _onTextChanged() {
    final atQuery = _getAtMentionQuery();
    if (atQuery != null) {
      _fileSearchDebounce?.cancel();
      _fileSearchDebounce = Timer(const Duration(milliseconds: 200), () {
        if (mounted) {
          _fetchMatchingFiles(atQuery);
        }
      });
    } else if (_matchingFiles.isNotEmpty) {
      _fileSearchDebounce?.cancel();
      setState(() {
        _matchingFiles = [];
        _isLoadingFiles = false;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _fetchMatchingFiles(String query) async {
    setState(() => _isLoadingFiles = true);
    try {
      final client = widget.client ?? AgyClient();
      final files = await client.searchWorkspaceFiles(query, limit: 30);
      if (mounted) {
        setState(() {
          _matchingFiles = files;
          _isLoadingFiles = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingFiles = false);
      }
    }
  }

  void _selectFileMention(Map<String, dynamic> file) {
    final relPath = file['relative_path'] as String? ?? file['name'] as String;
    final text = _controller.text;
    final sel = _controller.selection;
    final offset = sel.baseOffset >= 0 ? sel.baseOffset : text.length;
    final beforeCursor = text.substring(0, offset);
    final afterCursor = text.substring(offset);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex != -1) {
      final newBefore = beforeCursor.substring(0, atIndex);
      final replacement = '@[$relPath] ';
      _controller.text = '$newBefore$replacement$afterCursor';
      final newCursorPos = (newBefore + replacement).length;
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: newCursorPos));
    }
    setState(() {
      _matchingFiles = [];
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _attachments.add(ComposerAttachment(
            name: photo.name,
            path: photo.path,
            bytes: bytes,
            isImage: true,
            size: bytes.length,
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isNotEmpty) {
        for (final f in files) {
          final fileBytes = await f.readAsBytes();
          final ext = (f.extension ?? '').toLowerCase();
          final isImg = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(ext);
          setState(() {
            _attachments.add(ComposerAttachment(
              name: f.name,
              path: f.path,
              bytes: fileBytes,
              isImage: isImg,
              size: fileBytes.length,
            ));
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select file: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _fileSearchDebounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    _isSubmitting = true;
    _controller.clear();

    final lower = text.toLowerCase();
    if (lower == '/clear' || lower == '/reset') {
      widget.onClear?.call();
      _isSubmitting = false;
      return;
    }

    if (lower == '/help') {
      _showSlashCommands();
      _isSubmitting = false;
      return;
    }

    List<Map<String, dynamic>> uploadedAttachments = [];
    if (_attachments.isNotEmpty) {
      setState(() => _isUploading = true);
      try {
        final client = widget.client ?? AgyClient();
        for (final att in _attachments) {
          final res = await client.uploadMedia(att.bytes, att.name);
          uploadedAttachments.add(res);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }

    try {
      if (widget.isStreaming && widget.onSteer != null) {
        widget.onSteer!(text);
      } else {
        widget.onSend(text, _selectedModel, attachments: uploadedAttachments);
      }
    } finally {
      if (mounted) {
        setState(() {
          _attachments.clear();
          _matchingFiles = [];
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _isSubmitting = false;
        });
      } else {
        _isSubmitting = false;
      }
    }
  }

  void _selectCommand(String cmd) {
    _controller.text = '$cmd ';
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {});
  }


  List<Map<String, dynamic>> _getMatchingCommands(String rawText) {
    final trimmed = rawText.trim().toLowerCase();
    if (trimmed == '/' || trimmed.isEmpty) {
      return _commandsList;
    }
    final cleanQuery = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    final filtered = _commandsList.where((c) {
      final cmd = (c['command'] as String).toLowerCase();
      final name = (c['name'] as String? ?? '').toLowerCase();
      final desc = (c['description'] as String? ?? '').toLowerCase();
      return cmd.contains(trimmed) || name.contains(cleanQuery) || desc.contains(cleanQuery);
    }).toList();

    filtered.sort((a, b) {
      final cmdA = (a['command'] as String).toLowerCase();
      final cmdB = (b['command'] as String).toLowerCase();
      final startsA = cmdA.startsWith('/$cleanQuery');
      final startsB = cmdB.startsWith('/$cleanQuery');
      if (startsA && !startsB) return -1;
      if (!startsA && startsB) return 1;

      final isBuiltinA = a['category'] != 'skill';
      final isBuiltinB = b['category'] != 'skill';
      if (isBuiltinA && !isBuiltinB) return -1;
      if (!isBuiltinA && isBuiltinB) return 1;

      return cmdA.compareTo(cmdB);
    });

    return filtered;
  }

  void _showModelPicker() {
    String? expandedModelId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AgyTheme.getSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      'MODEL',
                      style: TextStyle(
                        color: AgyTheme.getTextSecondary(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_modelsList.length} AVAILABLE',
                      style: TextStyle(
                        color: AgyTheme.getTextSecondary(context).withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: AgyTheme.getBorder(context), height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _modelsList.length,
                  itemBuilder: (context, index) {
                    final item = _modelsList[index];
                    final isExpanded = expandedModelId == item.id;
                    final isSelected = item.displayName == _selectedModel ||
                        item.title == _selectedModel ||
                        (_selectedModel.startsWith(item.title) && item.tier != null && _selectedModel.contains(item.tier!));

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            if (item.hasArrow && item.variants.isNotEmpty) {
                              setModalState(() {
                                expandedModelId = isExpanded ? null : item.id;
                              });
                            } else {
                              setState(() => _selectedModel = item.displayName);
                              widget.onModelChanged?.call(item.displayName);
                              Navigator.pop(ctx);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          item.title,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AgyTheme.getTextPrimary(context),
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (item.tier != null) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          item.tier!,
                                          style: TextStyle(
                                            color: AgyTheme.getTextSecondary(context),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                      if (item.isFast) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AgyTheme.getSurfaceLight(context),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                                          ),
                                          child: Text(
                                            'Fast',
                                            style: TextStyle(
                                              color: AgyTheme.getTextSecondary(context),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check, size: 16, color: AgyTheme.getTextPrimary(context))
                                else if (item.hasArrow)
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                                    size: 16,
                                    color: AgyTheme.getTextSecondary(context).withValues(alpha: 0.4),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded && item.variants.isNotEmpty) ...[
                          Container(
                            margin: const EdgeInsets.only(left: 32, right: 20, bottom: 8),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: AgyTheme.getSurfaceLight(context).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: item.variants.map((variant) {
                                final isVariantSelected = _selectedModel.contains(variant.title) ||
                                    (variant.tier != null && _selectedModel.contains(variant.tier!));
                                return InkWell(
                                  onTap: () {
                                    final targetName = variant.tier != null
                                        ? '${item.title} ${variant.tier}'
                                        : variant.title;
                                    setState(() => _selectedModel = targetName);
                                    widget.onModelChanged?.call(targetName);
                                    Navigator.pop(ctx);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    child: Row(
                                      children: [
                                        Text(
                                          variant.tier ?? variant.title,
                                          style: TextStyle(
                                            color: isVariantSelected
                                                ? AgyTheme.getTextPrimary(context)
                                                : AgyTheme.getTextSecondary(context),
                                            fontSize: 12.5,
                                            fontWeight: isVariantSelected ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (isVariantSelected)
                                          Icon(Icons.check, size: 14, color: AgyTheme.getTextPrimary(context)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              Divider(color: AgyTheme.getBorder(context), height: 1),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (mounted) _showUsageModal();
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.speed, size: 16, color: AgyTheme.getTextSecondary(context)),
                      const SizedBox(width: 10),
                      Text(
                        'View Usage',
                        style: TextStyle(
                          color: AgyTheme.getTextPrimary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (_cachedQuota != null) ...[
                        Text(
                          _getQuickQuotaPreview(),
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(Icons.chevron_right, size: 16, color: AgyTheme.getTextSecondary(context).withValues(alpha: 0.4)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUsageModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AgyTheme.getSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            child: FutureBuilder<Map<String, dynamic>?>(
              future: AgyClient().getQuotaSummary(),
              builder: (context, snapshot) {
                final data = snapshot.data ?? _cachedQuota;
                final isLoading = snapshot.connectionState == ConnectionState.waiting && data == null;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.speed, size: 18, color: AgyTheme.getTextPrimary(context)),
                          const SizedBox(width: 8),
                          Text(
                            'API CREDITS & USAGE',
                            style: TextStyle(
                              color: AgyTheme.getTextPrimary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 0.8),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setSheetState(() {}),
                            child: Icon(Icons.refresh, size: 16, color: AgyTheme.getTextSecondary(context)),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: AgyTheme.getBorder(context), height: 1),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    else if (data == null || (data['groups'] as List?)?.isEmpty == true)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                        child: Center(
                          child: Text(
                            'Could not fetch usage metrics. Ensure Antigravity is running.',
                            style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(16),
                          children: [
                            ...((data['groups'] as List? ?? []).map((grp) {
                              final g = grp as Map<String, dynamic>;
                              final title = g['displayName'] as String? ?? 'Model Group';
                              final desc = g['description'] as String? ?? '';
                              final buckets = (g['buckets'] as List? ?? []).cast<Map<String, dynamic>>();

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AgyTheme.getSurfaceLight(context),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: AgyTheme.getTextPrimary(context),
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (desc.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        desc,
                                        style: TextStyle(
                                          color: AgyTheme.getTextSecondary(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    ...buckets.map((b) {
                                      final bName = b['displayName'] as String? ?? 'Limit';
                                      final bDesc = b['description'] as String? ?? '';
                                      final fraction = (b['remainingFraction'] as num?)?.toDouble() ?? 1.0;
                                      final pct = (fraction * 100).clamp(0, 100).toInt();

                                      Color barColor = const Color(0xFF10B981);
                                      if (pct < 20) {
                                        barColor = const Color(0xFFEF4444);
                                      } else if (pct < 50) {
                                        barColor = const Color(0xFFF59E0B);
                                      }

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  bName,
                                                  style: TextStyle(
                                                    color: AgyTheme.getTextPrimary(context),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  '$pct% Remaining',
                                                  style: TextStyle(
                                                    color: barColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: fraction.clamp(0.0, 1.0),
                                                minHeight: 5,
                                                backgroundColor: AgyTheme.getBorder(context),
                                                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                                              ),
                                            ),
                                            if (bDesc.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                bDesc,
                                                style: TextStyle(
                                                  color: AgyTheme.getTextSecondary(context).withValues(alpha: 0.8),
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              );
                            })),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AgyTheme.getSurface(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AgyTheme.getBorder(context).withValues(alpha: 0.5), width: 0.6),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, size: 14, color: AgyTheme.getTextSecondary(context)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      data['description'] as String? ??
                                          'Within each group, models share a weekly limit and a 5-hour limit. Quota is consumed proportionally to token cost. The 5-hour limit smooths out aggregate demand, while the weekly limit is tied to your individual account tier.',
                                      style: TextStyle(
                                        color: AgyTheme.getTextSecondary(context),
                                        fontSize: 10.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showAddActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AgyTheme.getSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.blueAccent),
              title: Text('Photo & Image Gallery', style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Pick image or screenshot to send', style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Colors.greenAccent),
              title: Text('Take Camera Photo', style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Capture photo with device camera', style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded, color: Colors.amberAccent),
              title: Text('Browse Device Files', style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Attach source code, logs, configs, or PDFs', style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFiles();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined, color: Colors.cyanAccent),
              title: Text('Reference Workspace File (@)', style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Mention project files directly in your prompt', style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                final cur = _controller.text;
                _controller.text = cur.isEmpty || cur.endsWith(' ') ? '$cur@' : '$cur @';
                _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
                _fetchMatchingFiles('');
              },
            ),
            ListTile(
              leading: const Icon(Icons.terminal_rounded, color: Colors.purpleAccent),
              title: Text('Insert Slash Command', style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Invoke specialized autonomous agent workflows', style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                Future.delayed(const Duration(milliseconds: 250), () {
                  if (mounted) _showSlashCommands();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSlashCommands() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AgyTheme.getSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.72,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AgyTheme.getBorder(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.terminal, size: 18, color: AgyTheme.getTextPrimary(context)),
                  const SizedBox(width: 8),
                  Text(
                    'Antigravity Slash Commands & Skills',
                    style: TextStyle(
                      color: AgyTheme.getTextPrimary(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Directives that unlock deep planning, goal running, and custom skills.',
                style: TextStyle(
                  color: AgyTheme.getTextSecondary(context),
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: AgyTheme.getBorder(context), height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: _commandsList.length,
                  separatorBuilder: (ctx, index) => Divider(
                    color: AgyTheme.getBorder(context).withValues(alpha: 0.4),
                    height: 1,
                  ),
                  itemBuilder: (ctx, idx) {
                    final c = _commandsList[idx];
                    final cmd = c['command'] as String;
                    final desc = c['description'] as String? ?? '';
                    final badge = c['badge'] as String? ?? 'CMD';
                    final icon = getCommandIcon(cmd);

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AgyTheme.getSurfaceLight(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                        ),
                        child: Icon(icon, size: 16, color: AgyTheme.getTextPrimary(context)),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              cmd,
                              style: TextStyle(
                                color: AgyTheme.getTextPrimary(context),
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AgyTheme.isDark(context) ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AgyTheme.getBorder(context), width: 0.6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                color: AgyTheme.getTextSecondary(context),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        desc,
                        style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _selectCommand(cmd);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAutocompleteOverlay(BuildContext context, List<Map<String, dynamic>> matches) {
    final isDark = AgyTheme.isDark(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.28,
      ),
      decoration: BoxDecoration(
        color: AgyTheme.getSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AgyTheme.getBorder(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black54 : Colors.black12,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: AgyTheme.getSurfaceLight(context),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 12, color: AgyTheme.getTextSecondary(context)),
                  const SizedBox(width: 6),
                  Text(
                    'COMMANDS & SKILLS (${matches.length})',
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tap to select',
                    style: TextStyle(
                      color: AgyTheme.getTextMuted(context),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: matches.length,
                separatorBuilder: (ctx, index) => Divider(
                  height: 1,
                  thickness: 0.5,
                  color: AgyTheme.getBorder(context).withValues(alpha: 0.4),
                ),
                itemBuilder: (ctx, idx) {
                  final item = matches[idx];
                  final cmd = item['command'] as String;
                  final badge = item['badge'] as String? ?? 'CMD';
                  final desc = item['description'] as String? ?? '';
                  final icon = getCommandIcon(cmd);

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _selectCommand(cmd),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AgyTheme.getSurfaceLight(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                            ),
                            child: Icon(icon, size: 13, color: AgyTheme.getTextPrimary(context)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        cmd,
                                        style: TextStyle(
                                          color: AgyTheme.getTextPrimary(context),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(color: AgyTheme.getBorder(context), width: 0.6),
                                      ),
                                      child: Text(
                                        badge,
                                        style: TextStyle(
                                          color: AgyTheme.getTextSecondary(context),
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    desc,
                                    style: TextStyle(
                                      color: AgyTheme.getTextMuted(context),
                                      fontSize: 10.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 10,
                            color: AgyTheme.getTextMuted(context),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceFileOverlay(BuildContext context, List<Map<String, dynamic>> files) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.28,
      ),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AgyTheme.getSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AgyTheme.getBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 14, color: Colors.cyanAccent),
                const SizedBox(width: 6),
                Text(
                  'WORKSPACE FILES (@)',
                  style: TextStyle(
                    color: AgyTheme.getTextSecondary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                if (_isLoadingFiles)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
                  Text(
                    '${files.length} found',
                    style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 10),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AgyTheme.getBorder(context)),
          Flexible(
            child: files.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No matching workspace files',
                      style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: files.length,
                    separatorBuilder: (_, index) => Divider(height: 1, color: AgyTheme.getBorder(context).withValues(alpha: 0.3)),
                    itemBuilder: (ctx, idx) {
                      final file = files[idx];
                      final name = file['name'] as String? ?? '';
                      final relPath = file['relative_path'] as String? ?? name;
                      final ext = (file['extension'] as String? ?? '').toLowerCase();
                      final isDir = file['is_directory'] as bool? ?? false;

                      IconData iconData = Icons.insert_drive_file_outlined;
                      Color iconColor = Colors.grey;
                      if (isDir) {
                        iconData = Icons.folder_outlined;
                        iconColor = Colors.cyanAccent;
                      } else if (ext == '.dart') {
                        iconData = Icons.flutter_dash;
                        iconColor = Colors.blueAccent;
                      } else if (ext == '.py') {
                        iconData = Icons.code;
                        iconColor = Colors.yellowAccent;
                      } else if (ext == '.json' || ext == '.yaml' || ext == '.yml') {
                        iconData = Icons.data_object;
                        iconColor = Colors.orangeAccent;
                      } else if (ext == '.md') {
                        iconData = Icons.description_outlined;
                        iconColor = Colors.purpleAccent;
                      } else if (['.png', '.jpg', '.jpeg', '.webp'].contains(ext)) {
                        iconData = Icons.image_outlined;
                        iconColor = Colors.greenAccent;
                      }

                      return ListTile(
                        dense: true,
                        leading: Icon(iconData, size: 18, color: iconColor),
                        title: Text(name, style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          relPath,
                          style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 10, fontFamily: 'monospace'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectFileMention(file),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentPreviewStrip() {
    if (_attachments.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final att = _attachments[idx];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: att.isImage ? 52 : 110,
                height: 52,
                decoration: BoxDecoration(
                  color: AgyTheme.getSurfaceLight(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AgyTheme.getBorder(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: att.isImage
                    ? Image.memory(
                        att.bytes,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file_outlined, size: 16, color: AgyTheme.getTextSecondary(context)),
                            const SizedBox(height: 2),
                            Text(
                              att.name,
                              style: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 10, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: GestureDetector(
                  onTap: () => setState(() => _attachments.removeAt(idx)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AgyTheme.isDark(context);
    final rawText = _controller.text;
    final isCommandTrigger = rawText.startsWith('/') && !rawText.contains(' ');
    final matchingCommands = isCommandTrigger ? _getMatchingCommands(rawText) : <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCommandTrigger && matchingCommands.isNotEmpty)
              _buildAutocompleteOverlay(context, matchingCommands),
            if (_matchingFiles.isNotEmpty)
              _buildWorkspaceFileOverlay(context, _matchingFiles),

            Container(
          decoration: BoxDecoration(
            color: AgyTheme.getSurface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AgyTheme.getBorder(context), width: 1),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Queued prompts indicator
              if (widget.queuedCount > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AgyTheme.getSurfaceLight(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 13, color: AgyTheme.getTextSecondary(context)),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.queuedCount} prompt${widget.queuedCount > 1 ? 's' : ''} queued (runs next)',
                        style: TextStyle(
                          color: AgyTheme.getTextSecondary(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Attached media and files preview strip
              _buildAttachmentPreviewStrip(),

              // Main input field
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  style: TextStyle(
                    color: AgyTheme.getTextPrimary(context),
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask anything, @ to mention, / for actions',
                    hintStyle: TextStyle(
                      color: AgyTheme.getTextMuted(context),
                      fontSize: 14,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),

              // Bottom control bar
              Builder(
                builder: (context) {
                  final hasText = _controller.text.trim().isNotEmpty;
                  final isSteerQueueMode = widget.isStreaming && hasText;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    child: Row(
                      children: [
                        // + Add Action Button
                        IconButton(
                          icon: Icon(Icons.add, size: 18, color: AgyTheme.getTextSecondary(context)),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Add attachment or action',
                          onPressed: _showAddActions,
                        ),

                        const SizedBox(width: 2),

                        // Model Chip (e.g. Gemini 3.8 Flash High ^) - ALWAYS FULL NAME
                        Flexible(
                          flex: 4,
                          fit: FlexFit.loose,
                          child: InkWell(
                            onTap: _showModelPicker,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                              decoration: BoxDecoration(
                                color: AgyTheme.getSurfaceLight(context),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _selectedModel,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: AgyTheme.getTextPrimary(context),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.keyboard_arrow_up,
                                    size: 13,
                                    color: AgyTheme.getTextSecondary(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const Spacer(flex: 1),

                        if (!isSteerQueueMode) ...[
                          // Mic Icon
                          IconButton(
                            icon: Icon(Icons.mic_none, size: 18, color: AgyTheme.getTextSecondary(context)),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            tooltip: 'Voice Input',
                            onPressed: () {},
                          ),
                          const SizedBox(width: 4),
                        ],

                        // Control Buttons: Steer / Queue / Stop / Send
                        if (isSteerQueueMode) ...[
                          // 1. Compact Stop
                          Tooltip(
                            message: 'Stop execution',
                            child: GestureDetector(
                              onTap: widget.onStop,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AgyTheme.getSurfaceLight(context),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.stop_rounded,
                                    size: 16,
                                    color: AgyTheme.getTextPrimary(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // 2. Queue Button
                          Tooltip(
                            message: 'Queue prompt for next turn',
                            child: GestureDetector(
                              onTap: () {
                                if (_isSubmitting) return;
                                final text = _controller.text.trim();
                                if (text.isNotEmpty) {
                                  _isSubmitting = true;
                                  _controller.clear();
                                  setState(() {});
                                  try {
                                    widget.onQueue?.call(text, _selectedModel);
                                  } finally {
                                    Future.delayed(const Duration(milliseconds: 300), () {
                                      if (mounted) _isSubmitting = false;
                                    });
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AgyTheme.getSurfaceLight(context),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.playlist_add_rounded, size: 14, color: AgyTheme.getTextPrimary(context)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Queue',
                                      style: TextStyle(
                                        color: AgyTheme.getTextPrimary(context),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // 3. Steer Button (Primary Action)
                          Tooltip(
                            message: 'Steer current agent turn immediately',
                            child: GestureDetector(
                              onTap: () {
                                if (_isSubmitting) return;
                                final text = _controller.text.trim();
                                if (text.isNotEmpty) {
                                  _isSubmitting = true;
                                  _controller.clear();
                                  setState(() {});
                                  try {
                                    widget.onSteer?.call(text);
                                  } finally {
                                    Future.delayed(const Duration(milliseconds: 300), () {
                                      if (mounted) _isSubmitting = false;
                                    });
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white : Colors.black,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.near_me_rounded,
                                      size: 13,
                                      color: isDark ? Colors.black : Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Steer',
                                      style: TextStyle(
                                        color: isDark ? Colors.black : Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ] else if (widget.isStreaming) ...[
                          // Idle streaming (no text typed yet): show Stop button
                          Tooltip(
                            message: 'Stop execution',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onStop,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white : Colors.black,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.stop_rounded,
                                    size: 16,
                                    color: isDark ? Colors.black : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ] else if (hasText || _attachments.isNotEmpty) ...[
                          // Normal ready-to-send button
                          Tooltip(
                            message: _isUploading ? 'Uploading attachments...' : 'Send prompt',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _isUploading ? null : _submit,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white : Colors.black,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: _isUploading
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: isDark ? Colors.black : Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          Icons.arrow_upward_rounded,
                                          size: 16,
                                          color: isDark ? Colors.black : Colors.white,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Muted send button
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AgyTheme.getSurfaceLight(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                size: 16,
                                color: AgyTheme.getTextMuted(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ),
  ),
);
}
}
