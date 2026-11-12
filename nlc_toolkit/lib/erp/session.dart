import 'dart:convert';

import 'erp_http.dart';
import 'firebase_auth_api.dart';
import 'secret_store.dart';

/// Compte connecté, tel qu'il est gardé d'une ouverture à l'autre.
class StoredSession {
  const StoredSession({
    required this.uid,
    required this.email,
    required this.refreshToken,
  });

  final String uid;
  final String email;
  final String refreshToken;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'email': email,
    'refreshToken': refreshToken,
  };

  static StoredSession? parse(Object? json) {
    if (json is! Map) return null;
    final uid = json['uid'];
    final email = json['email'];
    final refreshToken = json['refreshToken'];
    if (uid is! String || uid.isEmpty) return null;
    if (refreshToken is! String || refreshToken.isEmpty) return null;
    return StoredSession(
      uid: uid,
      email: email is String ? email : '',
      refreshToken: refreshToken,
    );
  }
}

/// Garde la session ouverte : conserve le jeton de longue durée, chiffré, et renouvelle le jeton
/// d'identité avant son expiration.
class SessionManager {
  SessionManager(this._auth, this._secrets, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final FirebaseAuthApi _auth;
  final SecretStore _secrets;
  final DateTime Function() _now;

  static const _storageKey = 'session';

  /// Le jeton d'identité est renouvelé quand il lui reste moins que cette durée.
  static const _renewBefore = Duration(minutes: 5);

  StoredSession? _session;
  String? _idToken;
  DateTime? _idTokenExpiry;
  Future<String>? _refreshing;

  /// Appelé quand le serveur refuse définitivement la session (compte désactivé, mot de passe
  /// changé, jeton révoqué). La session locale est déjà effacée.
  void Function(AuthException reason)? onInvalidated;

  StoredSession? get session => _session;

  /// Relit la session enregistrée. Renvoie `null` s'il n'y en a pas ou si elle est illisible.
  Future<StoredSession?> restore() async {
    final raw = await _secrets.read(_storageKey);
    if (raw == null) return _session = null;
    try {
      _session = StoredSession.parse(jsonDecode(raw));
    } on FormatException {
      _session = null;
    }
    if (_session == null) await _secrets.delete(_storageKey);
    return _session;
  }

  /// Ouvre la session avec les jetons d'une connexion réussie.
  Future<void> open(AuthTokens tokens) async {
    _session = StoredSession(
      uid: tokens.uid,
      email: tokens.email,
      refreshToken: tokens.refreshToken,
    );
    _idToken = tokens.idToken;
    _idTokenExpiry = tokens.expiresAt;
    await _persist();
  }

  /// Ferme la session et efface ce qui était enregistré.
  Future<void> close() async {
    _session = null;
    _idToken = null;
    _idTokenExpiry = null;
    _refreshing = null;
    await _secrets.delete(_storageKey);
  }

  /// Jeton d'identité valide, renouvelé si nécessaire.
  /// Lève une [AuthException] : `network` si le serveur est injoignable, sinon un refus définitif.
  Future<String> idToken() {
    final session = _session;
    if (session == null) {
      return Future.error(
        const AuthException(AuthFailure.sessionExpired, code: 'no-session'),
      );
    }
    final token = _idToken;
    final expiry = _idTokenExpiry;
    if (token != null &&
        expiry != null &&
        _now().isBefore(expiry.subtract(_renewBefore))) {
      return Future.value(token);
    }
    // Les appels simultanés partagent le même renouvellement.
    return _refreshing ??= _refresh(session)
        .whenComplete(() => _refreshing = null);
  }

  /// Même jeton, pour les services de données : les échecs deviennent des [ErpException].
  Future<String> idTokenForApi() async {
    try {
      return await idToken();
    } on AuthException catch (error) {
      throw ErpException(
        error.kind == AuthFailure.network
            ? ErpFailure.network
            : ErpFailure.unauthenticated,
        error.kind == AuthFailure.network
            ? 'Connexion au serveur impossible.'
            : 'La session a expiré.',
        code: error.code,
      );
    }
  }

  Future<String> _refresh(StoredSession session) async {
    final AuthTokens tokens;
    try {
      tokens = await _auth.refresh(session.refreshToken, email: session.email);
    } on AuthException catch (error) {
      if (error.kind == AuthFailure.sessionExpired ||
          error.kind == AuthFailure.userDisabled) {
        // Une autre connexion a pu ouvrir une nouvelle session pendant l'appel : ne pas l'effacer.
        if (identical(_session, session)) {
          await close();
          onInvalidated?.call(error);
        }
      }
      rethrow;
    }
    if (!identical(_session, session)) return tokens.idToken;
    _idToken = tokens.idToken;
    _idTokenExpiry = tokens.expiresAt;
    if (tokens.refreshToken != session.refreshToken) {
      _session = StoredSession(
        uid: session.uid,
        email: session.email,
        refreshToken: tokens.refreshToken,
      );
      await _persist();
    }
    return tokens.idToken;
  }

  Future<void> _persist() =>
      _secrets.write(_storageKey, jsonEncode(_session!.toJson()));
}
