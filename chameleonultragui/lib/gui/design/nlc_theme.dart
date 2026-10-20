import 'package:chameleonultragui/helpers/font.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared colours and component styling for the NLC Toolkit interface.
class NlcPalette {
  const NlcPalette._();

  static const darkCanvas = Color(0xFF0E1420);
  static const darkSurface = Color(0xFF171F2D);
  static const darkSurfaceRaised = Color(0xFF202B3B);
  static const darkBorder = Color(0xFF344257);
  static const darkText = Color(0xFFF4F7FC);
  static const darkMuted = Color(0xFFADBBCE);
  static const cyan = Color(0xFF35D1F4);
  static const violet = Color(0xFFA9A5F7);
  static const green = Color(0xFF4ED1A1);

  static const lightCanvas = Color(0xFFF5F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceRaised = Color(0xFFECF1F8);
  static const lightBorder = Color(0xFFD7E0EC);
  static const lightText = Color(0xFF14243C);
  static const lightMuted = Color(0xFF52647D);
  static const blue = Color(0xFF1769E8);
}

class NlcTheme {
  const NlcTheme._();

  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final canvas = isDark ? NlcPalette.darkCanvas : NlcPalette.lightCanvas;
    final surface = isDark ? NlcPalette.darkSurface : NlcPalette.lightSurface;
    final raised = isDark
        ? NlcPalette.darkSurfaceRaised
        : NlcPalette.lightSurfaceRaised;
    final border = isDark ? NlcPalette.darkBorder : NlcPalette.lightBorder;
    final ink = isDark ? NlcPalette.darkText : NlcPalette.lightText;
    final muted = isDark ? NlcPalette.darkMuted : NlcPalette.lightMuted;
    final accent = isDark ? NlcPalette.cyan : NlcPalette.blue;
    final onAccent = isDark ? NlcPalette.darkCanvas : Colors.white;
    final accentContainer = isDark
        ? const Color(0xFF173B49)
        : const Color(0xFFDDEAFF);

    final colors = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentContainer,
      onPrimaryContainer: ink,
      secondary: isDark ? NlcPalette.violet : const Color(0xFF6456BB),
      onSecondary: isDark ? NlcPalette.darkCanvas : Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerLowest: canvas,
      surfaceContainerLow: surface,
      surfaceContainer: raised,
      surfaceContainerHigh: raised,
      outline: border,
      outlineVariant: border,
      error: isDark ? const Color(0xFFFF8D99) : const Color(0xFFBD3344),
    );
    final borderRadius = BorderRadius.circular(18);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      dividerColor: border,
      disabledColor: muted.withValues(alpha: 0.46),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: canvas,
          statusBarBrightness: brightness,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: surface,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: raised,
          disabledForegroundColor: muted,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: accentContainer,
        selectedIconTheme: IconThemeData(color: accent, size: 24),
        unselectedIconTheme: IconThemeData(color: muted, size: 23),
        selectedLabelTextStyle:
            TextStyle(color: accent, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accentContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? accent : muted,
              size: 24,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected) ? accent : muted,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            )),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised,
        contentTextStyle: TextStyle(color: ink),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      listTileTheme: ListTileThemeData(
        iconColor: accent,
        textColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ).useCustomSystemFont(brightness);
  }
}
