import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/agy_client.dart';
import '../../core/theme/agy_theme.dart';
import '../../core/theme/language_icons.dart';
import '../../providers/workspace_provider.dart';

class FileViewerScreen extends ConsumerStatefulWidget {
  final String filePath;
  final String fileName;

  const FileViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  ConsumerState<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends ConsumerState<FileViewerScreen> {
  bool _isRawView = false;

  bool get _isImage {
    final lower = widget.fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg');
  }

  @override
  void initState() {
    super.initState();
    if (!_isImage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(workspaceProvider.notifier).openFile(widget.filePath, widget.fileName);
      });
    }
  }

  bool get _isMarkdown {
    final lower = widget.fileName.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown') || lower.endsWith('.plan') || lower.endsWith('.txt');
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(workspaceProvider);
    final isDark = AgyTheme.isDark(context);
    final content = wsState.openFileContent ?? '';

    return Scaffold(
      backgroundColor: AgyTheme.getBg(context),
      appBar: AppBar(
        backgroundColor: AgyTheme.getSurface(context),
        elevation: 0,
        title: Row(
          children: [
            LanguageFileIcon(filename: widget.fileName, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fileName,
                    style: TextStyle(
                      color: AgyTheme.getTextPrimary(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.filePath,
                    style: TextStyle(
                      color: AgyTheme.getTextMuted(context),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_isMarkdown)
            IconButton(
              icon: Icon(
                _isRawView ? Icons.visibility_outlined : Icons.code_outlined,
                color: AgyTheme.getTextPrimary(context),
                size: 20,
              ),
              tooltip: _isRawView ? 'Rendered View' : 'Raw View',
              onPressed: () => setState(() => _isRawView = !_isRawView),
            ),
          IconButton(
            icon: Icon(Icons.copy_outlined, color: AgyTheme.getTextPrimary(context), size: 18),
            tooltip: 'Copy Content',
            onPressed: content.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF27272A),
                        content: Text('File content copied to clipboard', style: TextStyle(color: Colors.white)),
                      ),
                    );
                  },
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: AgyTheme.getTextPrimary(context), size: 20),
            tooltip: 'Reload',
            onPressed: () => ref.read(workspaceProvider.notifier).openFile(widget.filePath, widget.fileName),
          ),
        ],
      ),
      body: _isImage
          ? Container(
              color: isDark ? const Color(0xFF090A0D) : const Color(0xFFF6F8FA),
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6.0,
                  child: Image.network(
                    AgyClient().getMediaUrl(widget.filePath),
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AgyTheme.getTextPrimary(context),
                        ),
                      );
                    },
                    errorBuilder: (ctx, err, stack) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined, size: 48, color: AgyTheme.getTextMuted(context)),
                          const SizedBox(height: 10),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.filePath,
                            style: TextStyle(color: AgyTheme.getTextMuted(context), fontSize: 11, fontFamily: 'monospace'),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          : wsState.isLoading
          ? Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AgyTheme.getTextPrimary(context),
              ),
            )
          : content.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_outlined, size: 40, color: AgyTheme.getTextMuted(context)),
                      const SizedBox(height: 12),
                      Text(
                        'No content available or file empty',
                        style: TextStyle(color: AgyTheme.getTextSecondary(context), fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => ref.read(workspaceProvider.notifier).openFile(widget.filePath, widget.fileName),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AgyTheme.getTextPrimary(context),
                          side: BorderSide(color: AgyTheme.getBorder(context)),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Container(
                  color: isDark ? const Color(0xFF090A0D) : const Color(0xFFF6F8FA),
                  width: double.infinity,
                  height: double.infinity,
                  child: (_isMarkdown && !_isRawView)
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: MarkdownBody(
                            data: content,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 13.5, height: 1.45),
                              h1: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 18, fontWeight: FontWeight.bold),
                              h2: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 16, fontWeight: FontWeight.bold),
                              h3: TextStyle(color: AgyTheme.getTextPrimary(context), fontSize: 14, fontWeight: FontWeight.bold),
                              code: TextStyle(
                                backgroundColor: isDark ? const Color(0xFF141416) : const Color(0xFFEEEEEE),
                                fontFamily: 'monospace',
                                color: AgyTheme.getTextPrimary(context),
                                fontSize: 12,
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: isDark ? const Color(0xFF121214) : const Color(0xFFF2F4F7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AgyTheme.getBorder(context)),
                              ),
                            ),
                          ),
                        )
                      : _buildDiffOrRawViewer(context, content, isDark),
                ),
    );
  }

  Widget _buildDiffOrRawViewer(BuildContext context, String content, bool isDark) {
    final lines = content.split('\n');
    final isDiff = lines.any((l) => l.startsWith('@@') || (l.startsWith('+') && !l.startsWith('+++')) || (l.startsWith('-') && !l.startsWith('---')));

    if (isDiff) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          Color textColor = AgyTheme.getTextSecondary(context);
          Color? bgColor;

          if (line.startsWith('+') && !line.startsWith('+++')) {
            textColor = const Color(0xFF22C55E); // Green for additions
            bgColor = const Color(0x1F22C55E);
          } else if (line.startsWith('-') && !line.startsWith('---')) {
            textColor = const Color(0xFFEF4444); // Red for deletions
            bgColor = const Color(0x1FEF4444);
          } else if (line.startsWith('@@')) {
            textColor = const Color(0xFF60A5FA); // Cyan for hunk header
            bgColor = const Color(0x1460A5FA);
          }

          return Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: AgyTheme.getTextMuted(context),
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    line,
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: AgyTheme.getTextPrimary(context),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
