import 'package:flutter/material.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/main.dart';

/// Bouton des fiches de carte : même allure que le bouton secondaire de l'ERP, texte aligné à gauche.
ButtonStyle customCardButtonStyle(NlcAppState appState) {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? Nlc.slate900.withValues(alpha: 0.55)
          : states.contains(WidgetState.hovered)
          ? Nlc.slate800
          : Nlc.slate900,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? Nlc.slate500 : Nlc.slate100,
    ),
    overlayColor: WidgetStateProperty.all(
      Nlc.indigo400.withValues(alpha: 0.10),
    ),
    side: WidgetStateProperty.all(const BorderSide(color: Nlc.border)),
    padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nlc.radius)),
    ),
  );
}
