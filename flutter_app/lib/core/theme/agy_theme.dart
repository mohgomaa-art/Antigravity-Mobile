import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void setMode(ThemeMode mode) {
    state = mode;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class AgyTheme {
  // ==========================================
  // Modern Monochrome Dark (Black Theme)
  // ==========================================
  static const Color darkBackground = Color(0xFF000000); // True deep black
  static const Color darkSidebarBg = Color(0xFF09090B);  // Pure dark zinc
  static const Color darkSurface = Color(0xFF121214);    // Pure dark zinc surface
  static const Color darkSurfaceLight = Color(0xFF18181B); // Zinc-900 surface light
  static const Color darkBorder = Color(0xFF27272A);      // Zinc-800 pure border
  static const Color darkBorderSubtle = Color(0xFF1E1E22); // Subtle border
  static const Color darkBorderLight = Color(0xFF3F3F46);  // Zinc-700 light border

  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA1A1AA); // Zinc-400
  static const Color darkTextMuted = Color(0xFF71717A);     // Zinc-500
  static const Color darkAccent = Color(0xFFFFFFFF);

  // ==========================================
  // Modern Antigravity PC Light Theme
  // ==========================================
  static const Color lightBackground = Color(0xFFFAFAFA); // Clean modern light background
  static const Color lightSidebarBg = Color(0xFFF4F4F5);  // Zinc-100 sidebar
  static const Color lightSurface = Color(0xFFFFFFFF);    // Pure white card surface
  static const Color lightSurfaceLight = Color(0xFFF4F4F5);
  static const Color lightBorder = Color(0xFFE4E4E7);     // Zinc-200 border
  static const Color lightBorderSubtle = Color(0xFFF4F4F5);
  static const Color lightBorderLight = Color(0xFFD4D4D8); // Zinc-300

  static const Color lightTextPrimary = Color(0xFF09090B); // Pure zinc black
  static const Color lightTextSecondary = Color(0xFF52525B); // Zinc-600
  static const Color lightTextMuted = Color(0xFF71717A);     // Zinc-500
  static const Color lightAccent = Color(0xFF09090B);

  // ==========================================
  // Static Fallback Aliases (Strict Monochrome)
  // ==========================================
  static const Color background = darkBackground;
  static const Color sidebarBg = darkSidebarBg;
  static const Color surface = darkSurface;
  static const Color surfaceLight = darkSurfaceLight;
  static const Color border = darkBorder;
  static const Color borderSubtle = darkBorderSubtle;
  static const Color borderLight = darkBorderLight;

  // Modern Monochrome Accents
  static const Color cyanAccent = Color(0xFFFFFFFF);
  static const Color blueAccent = Color(0xFFFFFFFF);
  static const Color violetAccent = Color(0xFFE5E7EB);
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);

  static const Color textPrimary = darkTextPrimary;
  static const Color textSecondary = darkTextSecondary;
  static const Color textMuted = darkTextMuted;

  // ==========================================
  // Context-Aware Dynamic Helpers
  // ==========================================
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color getBg(BuildContext context) =>
      isDark(context) ? darkBackground : lightBackground;

  static Color getSidebarBg(BuildContext context) =>
      isDark(context) ? darkSidebarBg : lightSidebarBg;

  static Color getSurface(BuildContext context) =>
      isDark(context) ? darkSurface : lightSurface;

  static Color getSurfaceLight(BuildContext context) =>
      isDark(context) ? darkSurfaceLight : lightSurfaceLight;

  static Color getBorder(BuildContext context) =>
      isDark(context) ? darkBorder : lightBorder;

  static Color getBorderSubtle(BuildContext context) =>
      isDark(context) ? darkBorderSubtle : lightBorderSubtle;

  static Color getTextPrimary(BuildContext context) =>
      isDark(context) ? darkTextPrimary : lightTextPrimary;

  static Color getTextSecondary(BuildContext context) =>
      isDark(context) ? darkTextSecondary : lightTextSecondary;

  static Color getTextMuted(BuildContext context) =>
      isDark(context) ? darkTextMuted : lightTextMuted;

  static Color getAccent(BuildContext context) =>
      isDark(context) ? darkAccent : lightAccent;

  // Diff & Code View Helpers
  static Color getDiffAddedBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF22C55E).withValues(alpha: 0.18) : const Color(0xFFDCFCE7);

  static Color getDiffAddedText(BuildContext context) =>
      isDark(context) ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);

  static Color getDiffRemovedBg(BuildContext context) =>
      isDark(context) ? const Color(0xFFEF4444).withValues(alpha: 0.18) : const Color(0xFFFEE2E2);

  static Color getDiffRemovedText(BuildContext context) =>
      isDark(context) ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  static Color getCodeBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF121214) : const Color(0xFFF6F8FA);

  static Color getCodeBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFF27272A) : const Color(0xFFE1E4E8);

  static Color getInlineCodeBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E1E22) : const Color(0xFFEAECF0);

  static Color getInlineCodeText(BuildContext context) =>
      isDark(context) ? const Color(0xFFE4E4E7) : const Color(0xFF1E293B);

  // ==========================================
  // ThemeData: Dark Monochrome
  // ==========================================
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: darkAccent,
      cardColor: darkSurface,
      dividerColor: darkBorder,
      colorScheme: const ColorScheme.dark(
        primary: darkAccent,
        secondary: Color(0xFFD4D4D8),
        surface: darkSurface,
        onSurface: darkTextPrimary,
        error: Color(0xFFFFFFFF),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: darkTextPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: darkTextPrimary,
        unselectedItemColor: darkTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  // ==========================================
  // ThemeData: Light Monochrome
  // ==========================================
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      primaryColor: lightAccent,
      cardColor: lightSurface,
      dividerColor: lightBorder,
      colorScheme: const ColorScheme.light(
        primary: lightAccent,
        secondary: Color(0xFF374151),
        surface: lightSurface,
        onSurface: lightTextPrimary,
        error: Color(0xFF000000),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: lightTextPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightBackground,
        selectedItemColor: lightTextPrimary,
        unselectedItemColor: lightTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 4,
      ),
    );
  }
}
