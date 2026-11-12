/// Identifiants des fichiers d'échange : dossiers de cartes, dossiers de dictionnaires et réglages
/// transmis par QR code.
///
/// Tout nouvel export porte l'identifiant NLC Toolkit. Les fichiers exportés avant ce changement
/// portaient un autre identifiant : ils restent acceptés à l'import pour ne perdre aucune sauvegarde.
class InterchangeFormat {
  const InterchangeFormat._();

  static const cardFolder = 'nlc-toolkit-folder';
  static const dictionaryFolder = 'nlc-toolkit-dictionary-folder';
  static const settingsQrHeader = 'NLC Toolkit Settings';

  // Anciens identifiants, en lecture seule.
  static const _legacyCardFolder = 'chameleon-ultra-gui-folder';
  static const _legacyDictionaryFolder =
      'chameleon-ultra-gui-dictionary-folder';
  static const _legacySettingsQrHeader = 'Chameleon Ultra GUI Settings';

  static bool isCardFolder(Object? format) =>
      format == cardFolder || format == _legacyCardFolder;

  static bool isDictionaryFolder(Object? format) =>
      format == dictionaryFolder || format == _legacyDictionaryFolder;

  /// Vrai si [qrData] est l'en-tête d'un export de réglages découpé en QR codes.
  static bool isSettingsQrHeader(String qrData) =>
      qrData.contains('"Info":"$settingsQrHeader"') ||
      qrData.contains('"Info":"$_legacySettingsQrHeader"');
}
