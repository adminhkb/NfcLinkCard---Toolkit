import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_controller.dart';
import 'badge_controller.dart';
import 'badge_dumps.dart';
import 'erp_config.dart';
import 'erp_directory.dart';
import 'erp_http.dart';
import 'firebase_auth_api.dart';
import 'firestore_api.dart';
import 'functions_api.dart';
import 'secret_store.dart';
import 'session.dart';
import 'storage_api.dart';
import 'trusted_device.dart';

/// Valeurs non secrètes rangées dans les préférences de l'application.
class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// Tout ce qui relie l'application à l'ERP, assemblé une fois au démarrage.
class ErpServices {
  ErpServices._({
    required this.config,
    required this.auth,
    required this.badges,
    required this.badgeDumps,
  });

  final ErpConfig config;
  final AuthController auth;
  final BadgeController badges;

  /// Enregistrement et lecture des dumps rattachés aux immeubles.
  final BadgeDumps badgeDumps;

  factory ErpServices.create({
    required ErpConfig config,
    required http.Client client,
    required SecretStore secrets,
    required KeyValueStore localState,
    String? userAgent,
    DateTime Function()? now,
  }) {
    final transport = ErpHttp(client, userAgent: userAgent);
    final authApi = FirebaseAuthApi(config, transport, now: now);
    final session = SessionManager(authApi, secrets, now: now);
    final firestore = FirestoreApi(config, transport, session.idTokenForApi);
    final storage = FirebaseStorageApi(
      config,
      transport,
      session.idTokenForApi,
    );
    final functions = FunctionsApi(config, transport, session.idTokenForApi);
    final directory = ErpDirectory(firestore, now: now);
    final auth = AuthController(
      auth: authApi,
      session: session,
      directory: directory,
      functions: functions,
      trustedDevices: TrustedDeviceStore(secrets),
      localState: localState,
      now: now,
    );
    return ErpServices._(
      config: config,
      auth: auth,
      badges: BadgeController(directory, auth, now: now),
      badgeDumps: BadgeDumps(
        firestore: firestore,
        storage: storage,
        auth: auth,
        now: now,
      ),
    );
  }
}
