import 'package:flutter/material.dart';
import 'agy_theme.dart';

class LanguageInfo {
  final String name;
  final Color color;
  final Color? secondaryColor;
  final IconData icon;
  final String label;
  final bool isBadge;

  const LanguageInfo({
    required this.name,
    required this.color,
    this.secondaryColor,
    required this.icon,
    required this.label,
    this.isBadge = false,
  });
}

class LanguageHelper {
  static LanguageInfo getLanguage(String filename) {
    final lower = filename.toLowerCase();

    // Python
    if (lower.endsWith('.py') || lower.endsWith('.pyw') || lower.endsWith('.pyi')) {
      return const LanguageInfo(
        name: 'Python',
        color: Color(0xFF3776AB),
        secondaryColor: Color(0xFFFFD43B),
        icon: Icons.code,
        label: 'PY',
        isBadge: true,
      );
    }

    // Dart / Flutter
    if (lower.endsWith('.dart')) {
      return const LanguageInfo(
        name: 'Dart',
        color: Color(0xFF0175C2),
        icon: Icons.flutter_dash,
        label: 'DART',
      );
    }

    // TypeScript
    if (lower.endsWith('.ts') || lower.endsWith('.tsx') || lower.endsWith('.mts') || lower.endsWith('.cts')) {
      return const LanguageInfo(
        name: 'TypeScript',
        color: Color(0xFF3178C6),
        icon: Icons.code,
        label: 'TS',
        isBadge: true,
      );
    }

    // JavaScript
    if (lower.endsWith('.js') || lower.endsWith('.jsx') || lower.endsWith('.mjs') || lower.endsWith('.cjs')) {
      return const LanguageInfo(
        name: 'JavaScript',
        color: Color(0xFFF7DF1E),
        icon: Icons.javascript,
        label: 'JS',
        isBadge: true,
      );
    }

    // JSON
    if (lower.endsWith('.json') || lower.endsWith('.jsonc') || lower.endsWith('.json5')) {
      return const LanguageInfo(
        name: 'JSON',
        color: Color(0xFFCBCB41),
        icon: Icons.data_object,
        label: '{ }',
      );
    }

    // Rust
    if (lower.endsWith('.rs')) {
      return const LanguageInfo(
        name: 'Rust',
        color: Color(0xFFDEA584),
        icon: Icons.settings_suggest,
        label: 'RS',
        isBadge: true,
      );
    }

    // Go
    if (lower.endsWith('.go')) {
      return const LanguageInfo(
        name: 'Go',
        color: Color(0xFF00ADD8),
        icon: Icons.bolt,
        label: 'GO',
        isBadge: true,
      );
    }

    // C
    if (lower.endsWith('.c') || lower.endsWith('.h')) {
      return const LanguageInfo(
        name: 'C',
        color: Color(0xFF00599C),
        icon: Icons.shield,
        label: 'C',
        isBadge: true,
      );
    }

    // C++
    if (lower.endsWith('.cpp') || lower.endsWith('.hpp') || lower.endsWith('.cc') || lower.endsWith('.cxx')) {
      return const LanguageInfo(
        name: 'C++',
        color: Color(0xFF659AD3),
        icon: Icons.shield,
        label: 'C++',
        isBadge: true,
      );
    }

    // C#
    if (lower.endsWith('.cs')) {
      return const LanguageInfo(
        name: 'C#',
        color: Color(0xFF239120),
        icon: Icons.code,
        label: 'C#',
        isBadge: true,
      );
    }

    // Java
    if (lower.endsWith('.java') || lower.endsWith('.jar') || lower.endsWith('.class')) {
      return const LanguageInfo(
        name: 'Java',
        color: Color(0xFFED8B00),
        icon: Icons.coffee,
        label: 'JAVA',
      );
    }

    // Kotlin
    if (lower.endsWith('.kt') || lower.endsWith('.kts')) {
      return const LanguageInfo(
        name: 'Kotlin',
        color: Color(0xFF7F52FF),
        icon: Icons.code,
        label: 'KT',
        isBadge: true,
      );
    }

    // Swift
    if (lower.endsWith('.swift')) {
      return const LanguageInfo(
        name: 'Swift',
        color: Color(0xFFF05138),
        icon: Icons.flight_takeoff,
        label: 'SWIFT',
      );
    }

    // Ruby
    if (lower.endsWith('.rb') || lower.endsWith('.erb') || lower == 'gemfile') {
      return const LanguageInfo(
        name: 'Ruby',
        color: Color(0xFFCC342D),
        icon: Icons.diamond,
        label: 'RB',
      );
    }

    // PHP
    if (lower.endsWith('.php') || lower.endsWith('.phtml')) {
      return const LanguageInfo(
        name: 'PHP',
        color: Color(0xFF777BB4),
        icon: Icons.code,
        label: 'PHP',
        isBadge: true,
      );
    }

    // HTML
    if (lower.endsWith('.html') || lower.endsWith('.htm') || lower.endsWith('.xhtml')) {
      return const LanguageInfo(
        name: 'HTML',
        color: Color(0xFFE34F26),
        icon: Icons.html,
        label: '</>',
      );
    }

    // CSS / SCSS
    if (lower.endsWith('.css')) {
      return const LanguageInfo(
        name: 'CSS',
        color: Color(0xFF1572B6),
        icon: Icons.css,
        label: '#',
      );
    }
    if (lower.endsWith('.scss') || lower.endsWith('.sass') || lower.endsWith('.less')) {
      return const LanguageInfo(
        name: 'SCSS',
        color: Color(0xFFCC6699),
        icon: Icons.style,
        label: 'S',
      );
    }

    // Markdown
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return const LanguageInfo(
        name: 'Markdown',
        color: Color(0xFF4A90E2),
        icon: Icons.article_outlined,
        label: 'M↓',
      );
    }

    // Shell / Bash / PowerShell
    if (lower.endsWith('.sh') || lower.endsWith('.bash') || lower.endsWith('.zsh')) {
      return const LanguageInfo(
        name: 'Shell',
        color: Color(0xFF4EAA25),
        icon: Icons.terminal,
        label: '>_',
      );
    }
    if (lower.endsWith('.ps1') || lower.endsWith('.bat') || lower.endsWith('.cmd')) {
      return const LanguageInfo(
        name: 'PowerShell',
        color: Color(0xFF012456),
        icon: Icons.terminal,
        label: 'PS',
        isBadge: true,
      );
    }

    // SQL / Database
    if (lower.endsWith('.sql') || lower.endsWith('.sqlite') || lower.endsWith('.db')) {
      return const LanguageInfo(
        name: 'SQL',
        color: Color(0xFF00758F),
        icon: Icons.storage,
        label: 'SQL',
      );
    }

    // Config / YAML / TOML
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return const LanguageInfo(
        name: 'YAML',
        color: Color(0xFFCB171E),
        icon: Icons.tune,
        label: 'YML',
      );
    }
    if (lower.endsWith('.toml') || lower.endsWith('.ini') || lower.endsWith('.cfg') || lower.endsWith('.env')) {
      return const LanguageInfo(
        name: 'Config',
        color: Color(0xFF6B7280),
        icon: Icons.settings,
        label: 'CFG',
      );
    }

    // Git
    if (lower.contains('.git') || lower == '.gitignore' || lower == '.gitattributes' || lower == '.gitmodules') {
      return const LanguageInfo(
        name: 'Git',
        color: Color(0xFFF05032),
        icon: Icons.alt_route,
        label: 'GIT',
      );
    }

    // Docker
    if (lower.contains('dockerfile') || lower.contains('docker-compose') || lower == '.dockerignore') {
      return const LanguageInfo(
        name: 'Docker',
        color: Color(0xFF2496ED),
        icon: Icons.directions_boat_outlined,
        label: 'DOCKER',
      );
    }

    // Images
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.webp') || lower.endsWith('.ico')) {
      return const LanguageInfo(
        name: 'Image',
        color: Color(0xFF26A69A),
        icon: Icons.image_outlined,
        label: 'IMG',
      );
    }
    if (lower.endsWith('.svg')) {
      return const LanguageInfo(
        name: 'SVG',
        color: Color(0xFFFF9900),
        icon: Icons.polyline,
        label: 'SVG',
      );
    }

    // Documents
    if (lower.endsWith('.pdf')) {
      return const LanguageInfo(
        name: 'PDF',
        color: Color(0xFFDC2626),
        icon: Icons.picture_as_pdf_outlined,
        label: 'PDF',
      );
    }

    // Archives
    if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      return const LanguageInfo(
        name: 'Archive',
        color: Color(0xFFF59E0B),
        icon: Icons.folder_zip_outlined,
        label: 'ZIP',
      );
    }

    // Default File
    return const LanguageInfo(
      name: 'File',
      color: Color(0xFF9CA3AF),
      icon: Icons.insert_drive_file_outlined,
      label: 'FILE',
    );
  }
}

/// A dedicated, colorful programming language file icon that matches Antigravity PC IDE
class LanguageFileIcon extends StatelessWidget {
  final String filename;
  final double size;

  const LanguageFileIcon({
    super.key,
    required this.filename,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageHelper.getLanguage(filename);

    if (lang.isBadge) {
      final isLightBg = lang.color.computeLuminance() > 0.5;
      return Container(
        width: size + 2,
        height: size + 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: lang.color,
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
        child: Text(
          lang.label,
          style: TextStyle(
            color: isLightBg ? Colors.black : Colors.white,
            fontSize: size * 0.55,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
            height: 1.0,
          ),
        ),
      );
    }

    return Icon(
      lang.icon,
      size: size,
      color: lang.color,
    );
  }
}

/// Polished File Edit Badge that matches Antigravity PC IDE's edited file view
class FileEditBadge extends StatelessWidget {
  final String filename;
  final int additions;
  final int deletions;
  final VoidCallback? onTap;

  const FileEditBadge({
    super.key,
    required this.filename,
    this.additions = 0,
    this.deletions = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AgyTheme.isDark(context);

    // Green addition badge colors
    final addBg = isDark
        ? const Color(0xFF22C55E).withValues(alpha: 0.18)
        : const Color(0xFFDCFCE7);
    final addFg = isDark
        ? const Color(0xFF4ADE80)
        : const Color(0xFF16A34A);

    // Red deletion badge colors
    final delBg = isDark
        ? const Color(0xFFEF4444).withValues(alpha: 0.18)
        : const Color(0xFFFEE2E2);
    final delFg = isDark
        ? const Color(0xFFF87171)
        : const Color(0xFFDC2626);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
        decoration: BoxDecoration(
          color: AgyTheme.getSurface(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AgyTheme.getBorder(context),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Colorful language icon
            LanguageFileIcon(filename: filename, size: 14),
            const SizedBox(width: 6),

            // Filename
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                filename,
                style: TextStyle(
                  color: AgyTheme.getTextPrimary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Additions tag (+N) & Deletions tag (-N)
            if (additions > 0 || deletions > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: addBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '+$additions',
                  style: TextStyle(
                    color: addFg,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: delBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '-$deletions',
                  style: TextStyle(
                    color: deletions > 0 ? delFg : (AgyTheme.isDark(context) ? Colors.white38 : Colors.black38),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
