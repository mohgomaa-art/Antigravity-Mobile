import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/theme/agy_theme.dart';

class ThoughtBubble extends StatefulWidget {
  final String thought;

  const ThoughtBubble({super.key, required this.thought});

  @override
  State<ThoughtBubble> createState() => _ThoughtBubbleState();
}

class _ThoughtBubbleState extends State<ThoughtBubble> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.thought.trim().isEmpty) return const SizedBox.shrink();

    final isDark = AgyTheme.isDark(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plain unboxed thinking header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Thinking',
                    style: TextStyle(
                      color: AgyTheme.getTextSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    size: 15,
                    color: AgyTheme.getTextMuted(context),
                  ),
                ],
              ),
            ),
          ),

          // Unboxed markdown thought content
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
              child: MarkdownBody(
                data: widget.thought,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: AgyTheme.getTextSecondary(context),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                  code: TextStyle(
                    backgroundColor: isDark ? const Color(0xFF1E1E22) : const Color(0xFFEAECF0),
                    color: AgyTheme.getTextPrimary(context),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isDark ? const Color(0xFF121214) : const Color(0xFFF6F8FA),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AgyTheme.getBorder(context), width: 0.8),
                  ),
                  listBullet: TextStyle(
                    color: AgyTheme.getTextSecondary(context),
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

