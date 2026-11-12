/// Projet Firebase de l'ERP et adresses de ses services.
///
/// Les identifiants du projet ne sont pas écrits dans le dépôt : ils sont fournis à la compilation
/// par `--dart-define-from-file=config/erp.json` (voir `config/erp.example.json`).
class ErpConfig {
  const ErpConfig({
    required this.projectId,
    required this.apiKey,
    required this.identityBase,
    required this.secureTokenBase,
    required this.firestoreBase,
    required this.functionsBase,
    required this.storageBase,
    required this.storageBucket,
    this.webAppUrl = '',
  });

  final String projectId;

  /// Clé d'API web du projet Firebase (identifie le projet, ne donne aucun droit à elle seule).
  final String apiKey;

  /// `https://identitytoolkit.googleapis.com/v1`
  final String identityBase;

  /// `https://securetoken.googleapis.com/v1`
  final String secureTokenBase;

  /// `https://firestore.googleapis.com/v1`
  final String firestoreBase;

  /// `https://<région>-<projet>.cloudfunctions.net`
  final String functionsBase;

  /// Racine de l'API REST Firebase Storage : `https://firebasestorage.googleapis.com`.
  final String storageBase;

  /// Bucket de stockage du projet, par exemple `mon-projet.firebasestorage.app`.
  final String storageBucket;

  /// Adresse de l'ERP dans le navigateur, pour les liens « Ouvrir dans l'ERP ».
  final String webAppUrl;

  bool get isConfigured => projectId.isNotEmpty && apiKey.isNotEmpty;

  /// Racine des documents Firestore du projet.
  String get documentsRoot =>
      '$firestoreBase/projects/$projectId/databases/(default)/documents';

  /// Racine des objets du bucket : `.../v0/b/<bucket>/o`.
  String get storageObjectsRoot =>
      '$storageBase/v0/b/${Uri.encodeComponent(storageBucket)}/o';

  /// Services en ligne du projet [projectId].
  factory ErpConfig.production({
    required String projectId,
    required String apiKey,
    String region = 'us-central1',
    String storageBucket = '',
    String webAppUrl = '',
  }) => ErpConfig(
    projectId: projectId,
    apiKey: apiKey,
    identityBase: 'https://identitytoolkit.googleapis.com/v1',
    secureTokenBase: 'https://securetoken.googleapis.com/v1',
    firestoreBase: 'https://firestore.googleapis.com/v1',
    functionsBase: 'https://$region-$projectId.cloudfunctions.net',
    storageBase: 'https://firebasestorage.googleapis.com',
    // À défaut d'indication, le bucket par défaut d'un projet récent.
    storageBucket: storageBucket.isEmpty
        ? '$projectId.firebasestorage.app'
        : storageBucket,
    webAppUrl: webAppUrl,
  );

  /// Émulateurs Firebase locaux (tests) : rien ne part vers le projet en ligne.
  factory ErpConfig.emulator({
    String projectId = 'demo-nlc',
    String host = '127.0.0.1',
    int authPort = 9099,
    int firestorePort = 8080,
    int functionsPort = 5001,
    int storagePort = 9199,
    String region = 'us-central1',
  }) => ErpConfig(
    projectId: projectId,
    apiKey: 'fake-api-key',
    identityBase: 'http://$host:$authPort/identitytoolkit.googleapis.com/v1',
    secureTokenBase: 'http://$host:$authPort/securetoken.googleapis.com/v1',
    firestoreBase: 'http://$host:$firestorePort/v1',
    functionsBase: 'http://$host:$functionsPort/$projectId/$region',
    storageBase: 'http://$host:$storagePort',
    storageBucket: '$projectId.firebasestorage.app',
  );

  /// Configuration reçue à la compilation. Vide si l'application a été compilée sans
  /// `--dart-define-from-file=config/erp.json`.
  factory ErpConfig.fromEnvironment() => ErpConfig.production(
    projectId: const String.fromEnvironment('NLC_ERP_PROJECT_ID'),
    apiKey: const String.fromEnvironment('NLC_ERP_API_KEY'),
    region: const String.fromEnvironment(
      'NLC_ERP_REGION',
      defaultValue: 'us-central1',
    ),
    storageBucket: const String.fromEnvironment('NLC_ERP_STORAGE_BUCKET'),
    webAppUrl: const String.fromEnvironment('NLC_ERP_WEB_URL'),
  );
}
