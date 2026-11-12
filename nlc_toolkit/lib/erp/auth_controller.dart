import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'erp_directory.dart';
import 'erp_http.dart';
import 'firebase_auth_api.dart';
import 'functions_api.dart';
import 'models.dart';
import 'session.dart';
import 'trusted_device.dart';

/// Où en est l'accès à l'application.
enum AuthStage {
  /// Lecture de la session enregistrée.
  starting,

  /// Écran de connexion.
  signedOut,

  /// Compte connecté : vérification de ses droits et de l'appareil.
  verifying,

  /// Écran du code de sécurité reçu par e-mail.
  secondFactor,

  /// Session enregistrée, mais l'ERP est injoignable et rien ne permet d'ouvrir l'application.
  unreachable,

  /// Application ouverte.
  ready,
}

/// Message à présenter à l'utilisateur, traduit par l'interface.
enum AuthNotice {
  invalidCredentials,
  userDisabled,
  tooManyAttempts,
  sessionExpired,
  notAuthorized,
  network,
  configuration,
  unsupportedSecondFactor,
  invalidCode,
  unknown,
}

class AuthUser {
  const AuthUser({required this.uid, required this.email});

  final String uid;
  final String email;
}

/// Petites valeurs non secrètes gardées d'une ouverture à l'autre (établissement actif, liste des
/// établissements pour l'ouverture hors connexion).
abstract class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  String? getString(String key) => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Connexion à l'ERP : même parcours que dans le navigateur.
///
/// 1. Firebase Auth vérifie l'adresse e-mail et le mot de passe.
/// 2. Le compte doit avoir accès à l'ERP (établissement, administrateur autorisé ou équipe).
/// 3. Double authentification : l'appareil mémorisé est vérifié par le serveur ; à défaut, un code
///    à six chiffres est envoyé par e-mail.
///
/// Hors connexion, l'application ne s'ouvre que si une session existe déjà et que cet appareil est
/// mémorisé : les outils NFC restent utilisables sur le terrain, sans les données de l'ERP.
class AuthController extends ChangeNotifier {
  AuthController({
    required FirebaseAuthApi auth,
    required SessionManager session,
    required ErpDirectory directory,
    required FunctionsApi functions,
    required TrustedDeviceStore trustedDevices,
    required KeyValueStore localState,
    DateTime Function()? now,
  }) : _auth = auth,
       _session = session,
       _directory = directory,
       _functions = functions,
       _trustedDevices = trustedDevices,
       _local = localState,
       _now = now ?? DateTime.now {
    _session.onInvalidated = _onSessionInvalidated;
  }

  final FirebaseAuthApi _auth;
  final SessionManager _session;
  final ErpDirectory _directory;
  final FunctionsApi _functions;
  final TrustedDeviceStore _trustedDevices;
  final KeyValueStore _local;
  final DateTime Function() _now;

  static const _activeIssuerKey = 'erp_active_issuer_id';
  static const _issuersCacheKey = 'erp_issuers_cache';

  /// Délai minimal entre deux envois du code, comme dans l'ERP.
  static const codeResendDelay = Duration(seconds: 60);

  AuthStage _stage = AuthStage.starting;
  AuthUser? _user;
  List<Issuer> _issuers = const [];
  Issuer? _currentIssuer;
  bool _isAdmin = false;
  bool _offline = false;
  bool _busy = false;
  AuthNotice? _notice;
  String? _noticeDetail;
  TrustNotice? _trustNotice;
  bool _sendingCode = false;
  DateTime? _codeSentAt;
  bool _secondFactorVerified = false;
  bool _hasTrustedDevice = false;
  bool _disposed = false;

  /// Change à chaque connexion ou déconnexion : une vérification lancée pour une session
  /// précédente abandonne en voyant que la valeur a changé.
  int _epoch = 0;

  AuthStage get stage => _stage;
  AuthUser? get user => _user;
  List<Issuer> get issuers => _issuers;
  Issuer? get currentIssuer => _currentIssuer;
  bool get isAdmin => _isAdmin;

  /// L'application est ouverte sans que l'ERP ait pu être joint : ses données ne sont pas disponibles.
  bool get offline => _offline;

  /// Une connexion ou une validation de code est en cours.
  bool get busy => _busy;

  /// Message de l'écran courant (connexion, code ou ERP injoignable).
  AuthNotice? get notice => _notice;

  /// Précision fournie par le serveur, déjà rédigée pour l'utilisateur.
  String? get noticeDetail => _noticeDetail;
  TrustNotice? get trustNotice => _trustNotice;
  bool get sendingCode => _sendingCode;
  DateTime? get codeSentAt => _codeSentAt;

  /// Cet appareil est mémorisé pour la double authentification.
  bool get hasTrustedDevice => _hasTrustedDevice;

  /// Jeton d'identité pour les appels de données.
  Future<String> idToken() => _session.idTokenForApi();

  /// Temps restant avant de pouvoir redemander un code.
  Duration get codeResendWait {
    final sentAt = _codeSentAt;
    if (sentAt == null) return Duration.zero;
    final wait = codeResendDelay - _now().difference(sentAt);
    return wait.isNegative ? Duration.zero : wait;
  }

  /// Reprend la session enregistrée, s'il y en a une.
  Future<void> start() async {
    final stored = await _session.restore();
    if (stored == null) {
      _set(stage: AuthStage.signedOut);
      return;
    }
    _user = AuthUser(uid: stored.uid, email: stored.email);
    _epoch += 1;
    await _verify(restoring: true);
  }

  Future<void> signIn(String email, String password) async {
    if (_busy) return;
    _busy = true;
    _notice = null;
    _noticeDetail = null;
    _notify();

    final AuthTokens tokens;
    try {
      tokens = await _auth.signInWithPassword(email.trim(), password);
    } on AuthException catch (error) {
      _busy = false;
      _notice = _noticeForAuth(error);
      _notify();
      return;
    }

    await _session.open(tokens);
    _epoch += 1;
    _user = AuthUser(uid: tokens.uid, email: tokens.email);
    _secondFactorVerified = false;
    _trustNotice = null;
    _codeSentAt = null;
    _busy = false;
    await _verify(restoring: false);
  }

  /// Relance la vérification après un échec de connexion à l'ERP.
  /// Depuis l'application ouverte hors connexion, la vérification se fait sans quitter l'écran.
  Future<void> retry() async {
    if (_user == null || _busy) return;
    await _verify(restoring: true, quiet: _stage == AuthStage.ready);
  }

  /// Envoie le code de sécurité par e-mail.
  Future<void> sendCode() async {
    if (_sendingCode || _user == null) return;
    final epoch = _epoch;
    _sendingCode = true;
    _notice = null;
    _noticeDetail = null;
    _notify();
    try {
      await _functions.call('sendAdmin2FACode');
      if (epoch != _epoch) return;
      _codeSentAt = _now();
    } on ErpException catch (error) {
      if (epoch != _epoch) return;
      if (error.kind == ErpFailure.permissionDenied) {
        // Le serveur refuse ce compte : même règle que l'écran de connexion.
        _sendingCode = false;
        await signOut(notice: AuthNotice.notAuthorized);
        return;
      }
      _applyError(error);
    } finally {
      if (epoch == _epoch) {
        _sendingCode = false;
        _notify();
      }
    }
  }

  /// Valide le code saisi. [rememberDevice] mémorise cet appareil pendant 30 jours.
  Future<bool> verifyCode(String code, {bool rememberDevice = false}) async {
    final user = _user;
    if (user == null || _busy) return false;
    final epoch = _epoch;
    _busy = true;
    _notice = null;
    _noticeDetail = null;
    _notify();

    try {
      final previous = rememberDevice
          ? await _trustedDevices.load(user.uid)
          : null;
      final result = await _functions.call('verifyAdmin2FACode', {
        'code': code.trim(),
        if (rememberDevice) 'rememberDevice': true,
        // L'ancien jeton de cet appareil est remplacé par le nouveau.
        'replaceDeviceId': ?previous?.deviceId,
      });
      if (epoch != _epoch) return false;

      if (result is Map && result['success'] == true) {
        if (rememberDevice) {
          final issued = TrustedDevice.parse(result['trustedDevice']);
          if (issued != null) {
            await _trustedDevices.save(user.uid, issued);
            _hasTrustedDevice = true;
          }
        }
        _secondFactorVerified = true;
        _trustNotice = null;
        _busy = false;
        _set(stage: AuthStage.ready);
        return true;
      }
      _notice = AuthNotice.invalidCode;
      final message = result is Map ? result['error'] : null;
      _noticeDetail = message is String && message.isNotEmpty ? message : null;
    } on ErpException catch (error) {
      if (epoch != _epoch) return false;
      _applyError(error);
    }
    _busy = false;
    _notify();
    return false;
  }

  /// Ferme la session. L'appareil reste mémorisé : le code ne sera pas redemandé à la reconnexion.
  Future<void> signOut({AuthNotice? notice}) async {
    _epoch += 1;
    await _session.close();
    _reset(notice: notice);
  }

  /// Cet appareil ne sera plus reconnu : le code sera redemandé à la prochaine ouverture.
  Future<void> forgetThisDevice() async {
    final user = _user;
    if (user == null) return;
    final device = await _trustedDevices.load(user.uid);
    if (device != null) {
      try {
        await _functions.call('revokeTrustedDevices', {
          'deviceId': device.deviceId,
        });
      } on ErpException {
        // Hors connexion : le jeton local est effacé ; le serveur l'oubliera à son expiration.
      }
    }
    await _trustedDevices.forget(user.uid);
    _hasTrustedDevice = false;
    _notify();
  }

  void selectIssuer(String issuerId) {
    final found = _issuers.where((issuer) => issuer.id == issuerId).firstOrNull;
    if (found == null || found.id == _currentIssuer?.id) return;
    _currentIssuer = found;
    unawaited(_local.setString(_activeIssuerKey, issuerId));
    _notify();
  }

  /* ─────────────── Vérification du compte et de l'appareil ─────────────── */

  Future<void> _verify({required bool restoring, bool quiet = false}) async {
    final user = _user;
    if (user == null) return;
    final epoch = _epoch;
    bool stale() => epoch != _epoch || _disposed;

    if (!quiet) {
      _notice = null;
      _noticeDetail = null;
      _offline = false;
      _set(stage: AuthStage.verifying);
    }

    final AccountProfile profile;
    try {
      profile = await _directory.loadProfile(user.uid);
    } on ErpException catch (error) {
      // Session refusée au renouvellement : _onSessionInvalidated a déjà ramené à l'écran de
      // connexion et changé d'époque, ce que stale() détecte.
      if (stale()) return;
      if (quiet) return;
      if (error.isOffline && restoring && await _canOpenOffline(user.uid)) {
        if (stale()) return;
        _openOffline(user.uid);
        return;
      }
      _applyError(error);
      _set(stage: AuthStage.unreachable);
      return;
    }
    if (stale()) return;

    if (!profile.allowed) {
      await signOut(notice: AuthNotice.notAuthorized);
      return;
    }
    _applyProfile(user.uid, profile);

    final device = await _trustedDevices.load(user.uid);
    if (stale()) return;
    _hasTrustedDevice = device != null;

    if (!_secondFactorVerified && device != null) {
      try {
        final verdict = interpretTrustCheck(
          await _functions.call('checkTrustedDevice', {
            'deviceId': device.deviceId,
            'token': device.token,
          }),
        );
        if (stale()) return;
        if (verdict.trusted) {
          _secondFactorVerified = true;
        } else if (verdict.forget) {
          await _trustedDevices.forget(user.uid);
          _hasTrustedDevice = false;
          _trustNotice = verdict.notice;
        }
      } on ErpException {
        // Pas de réponse définitive : le jeton est gardé pour la prochaine fois.
        if (stale()) return;
        if (quiet) return;
      }
    }

    _offline = false;
    _set(
      stage: _secondFactorVerified ? AuthStage.ready : AuthStage.secondFactor,
    );
  }

  /// Hors connexion, seul un appareil mémorisé et non expiré ouvre l'application.
  Future<bool> _canOpenOffline(String uid) async {
    final device = await _trustedDevices.load(uid);
    return device != null && !device.isExpiredAt(_now().millisecondsSinceEpoch);
  }

  void _openOffline(String uid) {
    _hasTrustedDevice = true;
    _issuers = _readIssuersCache(uid);
    _currentIssuer = _pickIssuer(_issuers);
    _offline = true;
    _notice = null;
    _noticeDetail = null;
    _set(stage: AuthStage.ready);
  }

  void _applyProfile(String uid, AccountProfile profile) {
    _isAdmin = profile.isAdmin;
    _issuers = profile.issuers;
    _currentIssuer = _pickIssuer(profile.issuers);
    unawaited(
      _local.setString(
        _issuersCacheKey,
        jsonEncode({
          'uid': uid,
          'issuers': profile.issuers.map((i) => i.toJson()).toList(),
        }),
      ),
    );
  }

  /// L'établissement choisi la dernière fois, sinon le premier de la liste.
  Issuer? _pickIssuer(List<Issuer> issuers) {
    if (issuers.isEmpty) return null;
    final saved = _local.getString(_activeIssuerKey);
    final current = _currentIssuer?.id;
    return issuers.where((i) => i.id == current).firstOrNull ??
        issuers.where((i) => i.id == saved).firstOrNull ??
        issuers.first;
  }

  List<Issuer> _readIssuersCache(String uid) {
    final raw = _local.getString(_issuersCacheKey);
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['uid'] != uid || json['issuers'] is! List) {
        return const [];
      }
      return [
        for (final item in json['issuers'] as List) ?Issuer.fromJson(item),
      ];
    } on FormatException {
      return const [];
    }
  }

  /* ─────────────── État ─────────────── */

  void _onSessionInvalidated(AuthException reason) {
    _epoch += 1;
    _reset(
      notice: reason.kind == AuthFailure.userDisabled
          ? AuthNotice.userDisabled
          : AuthNotice.sessionExpired,
    );
  }

  void _reset({AuthNotice? notice}) {
    _user = null;
    _issuers = const [];
    _currentIssuer = null;
    _isAdmin = false;
    _offline = false;
    _busy = false;
    _sendingCode = false;
    _codeSentAt = null;
    _secondFactorVerified = false;
    _hasTrustedDevice = false;
    _trustNotice = null;
    _notice = notice;
    _noticeDetail = null;
    _set(stage: AuthStage.signedOut);
  }

  void _applyError(ErpException error) {
    if (error.isOffline) {
      _notice = AuthNotice.network;
      _noticeDetail = null;
    } else {
      _notice = AuthNotice.unknown;
      _noticeDetail = error.message;
    }
  }

  static AuthNotice _noticeForAuth(AuthException error) => switch (error.kind) {
    AuthFailure.invalidCredentials => AuthNotice.invalidCredentials,
    AuthFailure.userDisabled => AuthNotice.userDisabled,
    AuthFailure.tooManyAttempts => AuthNotice.tooManyAttempts,
    AuthFailure.sessionExpired => AuthNotice.sessionExpired,
    AuthFailure.unsupportedSecondFactor => AuthNotice.unsupportedSecondFactor,
    AuthFailure.configuration => AuthNotice.configuration,
    AuthFailure.network => AuthNotice.network,
    AuthFailure.unknown => AuthNotice.unknown,
  };

  void _set({required AuthStage stage}) {
    _stage = stage;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session.onInvalidated = null;
    super.dispose();
  }
}
