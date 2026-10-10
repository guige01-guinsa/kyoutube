import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class ScoutStyle {
  // Ivory, plum and apricot: shared by personal and business workspaces.
  static const ink = Color(0xFF332A32);
  static const plum = Color(0xFF69445F);
  static const blush = Color(0xFFF0E6EC);
  static const cream = Color(0xFFFBF8F3);
  static const peach = Color(0xFFF4D6C0);
  static const muted = Color(0xFF746871);
  static const line = Color(0xFFE7DDDF);
  // Compatibility aliases for existing feature widgets.
  static const forest = plum;
  static const mint = blush;
  static const sidebar = cream;
  static const sidebarForeground = ink;
  static const sidebarMuted = muted;
  static const selection = blush;
  static const readingWidth = 840.0;
  static const formWidth = 900.0;
  static const workspaceWidth = 1200.0;
  static const sidebarWidth = 246.0;
  static const desktopBreakpoint = 1100.0;
  static const contentWidth = readingWidth;
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
            seedColor: ScoutStyle.forest, brightness: Brightness.light)
        .copyWith(
      primary: ScoutStyle.forest,
      onPrimary: Colors.white,
      primaryContainer: ScoutStyle.mint,
      onPrimaryContainer: ScoutStyle.ink,
      secondaryContainer: ScoutStyle.peach,
      onSecondaryContainer: ScoutStyle.ink,
      surface: const Color(0xFFFFFFFF),
      onSurface: ScoutStyle.ink,
      onSurfaceVariant: ScoutStyle.muted,
      outline: const Color(0xFF9A8994),
      outlineVariant: ScoutStyle.line,
    );
    final base = ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: kIsWeb ? 'RecipeScoutKR' : null);
    final text = base.textTheme
        .apply(bodyColor: ScoutStyle.ink, displayColor: ScoutStyle.ink);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return base.copyWith(
      scaffoldBackgroundColor: ScoutStyle.cream,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800, height: 1.3, letterSpacing: -1),
        headlineSmall: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800, height: 1.35, letterSpacing: -0.6),
        titleLarge: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700, height: 1.35, letterSpacing: -0.5),
        titleMedium: text.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700, height: 1.4),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.6),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
        bodySmall:
            text.bodySmall?.copyWith(height: 1.5, color: ScoutStyle.muted),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
          backgroundColor: ScoutStyle.cream,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          toolbarHeight: 64,
          centerTitle: false,
          titleSpacing: 20,
          titleTextStyle: text.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, fontSize: 20)),
      cardTheme: CardThemeData(
          color: scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: ScoutStyle.line))),
      dividerTheme:
          const DividerThemeData(color: ScoutStyle.line, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: ScoutStyle.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: ScoutStyle.forest, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: shape,
              textStyle:
                  text.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: shape,
              side: const BorderSide(color: ScoutStyle.line))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: ScoutStyle.forest,
          foregroundColor: Colors.white,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: scheme.surface,
          indicatorColor: ScoutStyle.mint,
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStatePropertyAll(
              text.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
      tabBarTheme: TabBarThemeData(
          labelColor: ScoutStyle.forest,
          unselectedLabelColor: ScoutStyle.muted,
          dividerColor: ScoutStyle.line,
          labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      chipTheme: base.chipTheme.copyWith(
          side: BorderSide.none,
          shape: const StadiumBorder(),
          backgroundColor: scheme.surface,
          selectedColor: ScoutStyle.selection,
          labelStyle: text.labelMedium),
      listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          minVerticalPadding: 8),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: scheme.surface, showDragHandle: true),
    );
  }
}
