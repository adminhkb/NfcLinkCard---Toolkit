import 'package:flutter/material.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';

ButtonStyle customCardButtonStyle(ChameleonGUIState appState) {
  final selectedTheme = appState.sharedPreferencesProvider.getTheme();
  final isDark =
      selectedTheme == ThemeMode.dark ||
      (selectedTheme == ThemeMode.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);
  final surface = isDark
      ? NlcPalette.darkSurfaceRaised
      : NlcPalette.lightSurfaceRaised;
  final border = isDark ? NlcPalette.darkBorder : NlcPalette.lightBorder;
  final text = isDark ? NlcPalette.darkText : NlcPalette.lightText;
  final muted = isDark ? NlcPalette.darkMuted : NlcPalette.lightMuted;
  final accent = isDark ? NlcPalette.cyan : NlcPalette.blue;

  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? surface.withValues(alpha: 0.55)
          : surface,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? muted : text,
    ),
    overlayColor: WidgetStateProperty.all(accent.withValues(alpha: 0.10)),
    side: WidgetStateProperty.all(BorderSide(color: border)),
    padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
