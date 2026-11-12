import 'package:flutter/material.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';

/// Pages de l'application.
enum NlcDestination {
  dashboard(Icons.home_outlined, Icons.home_rounded),
  read(Icons.nfc_outlined, Icons.nfc_rounded, needsDevice: true),
  write(Icons.edit_outlined, Icons.edit_rounded, needsDevice: true),
  library(
    Icons.folder_copy_outlined,
    Icons.folder_copy_rounded,
    advanced: true,
  ),
  device(Icons.memory_outlined, Icons.memory_rounded, advanced: true),
  slots(
    Icons.view_carousel_outlined,
    Icons.view_carousel_rounded,
    advanced: true,
    needsDevice: true,
  ),
  tools(
    Icons.construction_outlined,
    Icons.construction_rounded,
    advanced: true,
  ),
  debug(Icons.bug_report_outlined, Icons.bug_report_rounded, advanced: true),
  settings(Icons.settings_outlined, Icons.settings_rounded);

  const NlcDestination(
    this.icon,
    this.selectedIcon, {
    this.advanced = false,
    this.needsDevice = false,
  });

  final IconData icon;
  final IconData selectedIcon;

  /// Visible dans le menu en mode avancé seulement.
  final bool advanced;

  /// A besoin du lecteur connecté.
  final bool needsDevice;

  String label(AppLocalizations l) => switch (this) {
    NlcDestination.dashboard => l.home,
    NlcDestination.read => l.read_card,
    NlcDestination.write => l.write_card,
    NlcDestination.library => l.nlc_nav_library,
    NlcDestination.device => l.nlc_nav_device,
    NlcDestination.slots => l.nlc_nav_slots,
    NlcDestination.tools => l.tools,
    NlcDestination.debug => l.debug,
    NlcDestination.settings => l.settings,
  };

  static NlcDestination? byName(String? name) {
    for (final destination in values) {
      if (destination.name == name) return destination;
    }
    return null;
  }
}

/// Page affichée. Les pages changent de destination par `context.read<NlcNavigation>().go(...)`.
class NlcNavigation extends ChangeNotifier {
  NlcNavigation([this._current = NlcDestination.dashboard]);

  NlcDestination _current;

  NlcDestination get current => _current;

  void go(NlcDestination destination) {
    if (destination == _current) return;
    _current = destination;
    notifyListeners();
  }
}
