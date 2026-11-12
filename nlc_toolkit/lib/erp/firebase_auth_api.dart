import 'erp_config.dart';
import 'erp_http.dart';

/// Pourquoi une connexion ou un renouvellement de session a échoué.
enum AuthFailure {
  /// Adresse e-mail ou mot de passe incorrect.
  invalidCredentials,
  userDisabled,
  tooManyAttempts,

  /// La session enregistrée n'est plus valable : il faut se reconnecter.
  sessionExpired,

  /// Le compte exige une validation en deux étapes native de Firebase, que l'ERP n'utilise pas.
  unsupportedSecondFactor,

  /// Clé d'API refusée ou application compilée sans configuration.
  configuration,
  network,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.kind, {this.code});

  final AuthFailure kind;

  /// Code brut renvoyé par Firebase, pour le journal.
  final String? code;

  @override
  String toString() =>
      'AuthException(${kind.name}${code == null ? '' : ', $code'})';
}

/// Jetons délivrés par Firebase Auth pour un compte.
class AuthTokens {
  const AuthTokens({
    required this.uid,
    required this.email,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String uid;
  final String email;

  /// Jeton d'identité, valable une heure, présenté à Firestore et aux fonctions.
  final String idToken;

  /// Jeton de longue durée qui permet d'obtenir de nouveaux jetons d'identité.
  final String refreshToken;
  final DateTime expiresAt;
}

/// Firebase Auth par son interface REST : connexion par e-mail et mot de passe, renouvellement.
class FirebaseAuthApi {
  FirebaseAuthApi(this._config, this._http, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ErpConfig _config;
  final ErpHttp _http;
  final DateTime Function() _now;

  Future<AuthTokens> signInWithPassword(String email, String password) async {
    final url = Uri.parse('${_config.identityBase}/accounts:signInWithPassword')
        .replace(queryParameters: {'key': _config.apiKey});
    final json = await _call(
      () => _http.postJson(url, {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    final idToken = json['idToken'];
    final refreshToken = json['refreshToken'];
    final uid = json['localId'];
    if (idToken is! String || refreshToken is! String || uid is! String) {
      if (json['mfaPendingCredential'] != null) {
        throw const AuthException(AuthFailure.unsupportedSecondFactor);
      }
      throw const AuthException(
        AuthFailure.unknown,
        code: 'incomplete-response',
      );
    }
    return AuthTokens(
      uid: uid,
      email: json['email'] is String ? json['email'] as String : email,
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: _expiry(json['expiresIn']),
    );
  }

  /// Échange le jeton de longue durée contre un nouveau jeton d'identité.
  Future<AuthTokens> refresh(
    String refreshToken, {
    required String email,
  }) async {
    final url = Uri.parse('${_config.secureTokenBase}/token')
        .replace(queryParameters: {'key': _config.apiKey});
    final json = await _call(
      () => _http.postForm(url, {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      }),
      refreshing: true,
    );

    final idToken = json['id_token'];
    final uid = json['user_id'];
    if (idToken is! String || uid is! String) {
      throw const AuthException(
        AuthFailure.unknown,
        code: 'incomplete-response',
      );
    }
    final renewed = json['refresh_token'];
    return AuthTokens(
      uid: uid,
      email: email,
      idToken: idToken,
      refreshToken: renewed is String && renewed.isNotEmpty
          ? renewed
          : refreshToken,
      expiresAt: _expiry(json['expires_in']),
    );
  }

  DateTime _expiry(Object? seconds) {
    final value = seconds is num
        ? seconds.toInt()
        : int.tryParse('$seconds') ?? 3600;
    return _now().add(Duration(seconds: value));
  }

  Future<Map<String, dynamic>> _call(
    Future<ErpResponse> Function() request, {
    bool refreshing = false,
  }) async {
    final ErpResponse response;
    try {
      response = await request();
    } on ErpException catch (error) {
      throw AuthException(
        error.isOffline ? AuthFailure.network : AuthFailure.unknown,
        code: error.code,
      );
    }

    final json = response.json;
    if (response.ok && json is Map) return Map<String, dynamic>.from(json);

    final error = erpErrorBody(json);
    final message = error?['message'];
    throw AuthException(
      _classify(message is String ? message : '', response.status, refreshing),
      code: message is String ? message : 'http-${response.status}',
    );
  }

  static AuthFailure _classify(String message, int status, bool refreshing) {
    // Certains messages portent une explication après le code : « CODE : détail ».
    final code = message.split(RegExp(r'[\s:]')).first.toUpperCase();
    switch (code) {
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_PASSWORD':
      case 'INVALID_EMAIL':
      case 'MISSING_EMAIL':
      case 'MISSING_PASSWORD':
        return AuthFailure.invalidCredentials;
      case 'USER_DISABLED':
        return AuthFailure.userDisabled;
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return AuthFailure.tooManyAttempts;
      case 'TOKEN_EXPIRED':
      case 'USER_NOT_FOUND':
      case 'INVALID_REFRESH_TOKEN':
      case 'MISSING_REFRESH_TOKEN':
      case 'INVALID_GRANT_TYPE':
      case 'CREDENTIAL_TOO_OLD_LOGIN_AGAIN':
        return AuthFailure.sessionExpired;
      case 'API_KEY_HTTP_REFERRER_BLOCKED':
      case 'API_KEY_SERVICE_BLOCKED':
      case 'CONFIGURATION_NOT_FOUND':
      case 'OPERATION_NOT_ALLOWED':
      case 'PROJECT_NOT_FOUND':
        return AuthFailure.configuration;
    }
    if (message.toLowerCase().contains('api key')) {
      return AuthFailure.configuration;
    }
    if (status == 403) return AuthFailure.configuration;
    if (status >= 500) return AuthFailure.network;
    // Un renouvellement refusé sans raison connue : mieux vaut redemander les identifiants.
    return refreshing && status == 400
        ? AuthFailure.sessionExpired
        : AuthFailure.unknown;
  }
}
