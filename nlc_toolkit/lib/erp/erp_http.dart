import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Nature d'un échec d'appel à l'ERP, indépendante du service appelé.
enum ErpFailure {
  /// Pas de réseau, serveur injoignable ou délai dépassé.
  network,

  /// Jeton absent, expiré ou refusé.
  unauthenticated,

  /// Le compte n'a pas le droit de faire cette opération.
  permissionDenied,
  notFound,
  invalidArgument,
  failedPrecondition,

  /// Trop de demandes : réessayer plus tard.
  rateLimited,
  server,
  unknown,
}

class ErpException implements Exception {
  const ErpException(this.kind, this.message, {this.code, this.httpStatus});

  final ErpFailure kind;

  /// Message destiné à l'utilisateur quand le serveur en fournit un, sinon message technique.
  final String message;

  /// Code brut renvoyé par le service (`PERMISSION_DENIED`, `INVALID_LOGIN_CREDENTIALS`…).
  final String? code;
  final int? httpStatus;

  bool get isOffline => kind == ErpFailure.network;

  @override
  String toString() =>
      'ErpException(${kind.name}${code == null ? '' : ', $code'}): $message';
}

/// Réponse HTTP décodée. [json] vaut `null` si le corps n'est pas du JSON.
class ErpResponse {
  const ErpResponse(this.status, this.body, this.json);

  final int status;
  final String body;
  final Object? json;

  bool get ok => status >= 200 && status < 300;
}

/// Réponse binaire : corps non décodé (téléchargement d'un objet Storage).
class ErpBytes {
  const ErpBytes(this.status, this.bytes);

  final int status;
  final Uint8List bytes;

  bool get ok => status >= 200 && status < 300;
}

/// Nom du système tel que l'ERP le reconnaît dans la liste des appareils mémorisés.
String erpPlatformLabel() {
  if (Platform.isWindows) return 'Windows';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iPhone';
  if (Platform.isMacOS) return 'Macintosh';
  if (Platform.isLinux) return 'Linux';
  return Platform.operatingSystem;
}

/// Client HTTP commun aux services de l'ERP : JSON, délai maximal et erreurs réseau uniformes.
class ErpHttp {
  ErpHttp(
    this._client, {
    String? userAgent,
    this.timeout = const Duration(seconds: 20),
  }) : userAgent = userAgent ?? 'NLC Toolkit (${erpPlatformLabel()})';

  final http.Client _client;
  final String userAgent;
  final Duration timeout;

  Future<ErpResponse> get(Uri url, {String? bearer}) =>
      _send(() => _client.get(url, headers: _headers(bearer)));

  Future<ErpResponse> postJson(Uri url, Object? body, {String? bearer}) =>
      _send(
        () => _client.post(
          url,
          headers: {
            ..._headers(bearer),
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(body),
        ),
      );

  Future<ErpResponse> postForm(Uri url, Map<String, String> fields) =>
      _send(() => _client.post(url, headers: _headers(null), body: fields));

  /// PATCH d'un corps JSON (écriture d'un document Firestore).
  Future<ErpResponse> patchJson(Uri url, Object? body, {String? bearer}) =>
      _send(
        () => _client.patch(
          url,
          headers: {
            ..._headers(bearer),
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(body),
        ),
      );

  /// DELETE d'une URL. Les en-têtes fournis complètent le User-Agent (schéma
  /// d'autorisation propre à Storage, par exemple).
  Future<ErpResponse> delete(
    Uri url, {
    String? bearer,
    Map<String, String> headers = const {},
  }) => _send(
    () => _client.delete(url, headers: {..._headers(bearer), ...headers}),
  );

  /// POST d'un corps binaire (téléversement d'un objet Storage). La réponse reste du JSON
  /// (métadonnées de l'objet). Les [headers] fournis portent le type de contenu et l'autorisation.
  Future<ErpResponse> postBytes(
    Uri url,
    List<int> body, {
    Map<String, String> headers = const {},
  }) => _send(
    () => _client.post(
      url,
      headers: {'User-Agent': userAgent, ...headers},
      body: body,
    ),
  );

  /// GET renvoyant le corps binaire sans le décoder (téléchargement d'un objet Storage).
  Future<ErpBytes> getBytes(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _run(
      () => _client.get(url, headers: {'User-Agent': userAgent, ...headers}),
    );
    return ErpBytes(response.statusCode, response.bodyBytes);
  }

  Map<String, String> _headers(String? bearer) => {
    'Accept': 'application/json',
    'User-Agent': userAgent,
    if (bearer != null) 'Authorization': 'Bearer $bearer',
  };

  /// Exécute la requête en traduisant toute panne réseau en [ErpException].
  Future<http.Response> _run(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const ErpException(ErpFailure.network, 'Le serveur ne répond pas.');
    } on SocketException catch (error) {
      throw ErpException(
        ErpFailure.network,
        'Connexion impossible : ${error.message}',
      );
    } on HandshakeException catch (error) {
      throw ErpException(
        ErpFailure.network,
        'Connexion sécurisée impossible : ${error.message}',
      );
    } on http.ClientException catch (error) {
      throw ErpException(
        ErpFailure.network,
        'Connexion impossible : ${error.message}',
      );
    }
  }

  Future<ErpResponse> _send(Future<http.Response> Function() request) async {
    final response = await _run(request);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? decoded;
    if (body.isNotEmpty) {
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        decoded = null;
      }
    }
    return ErpResponse(response.statusCode, body, decoded);
  }
}

/// Traduit un statut gRPC (`PERMISSION_DENIED`…) ou, à défaut, un code HTTP.
ErpFailure erpFailureFrom(String? status, int httpStatus) {
  switch (status) {
    case 'UNAUTHENTICATED':
      return ErpFailure.unauthenticated;
    case 'PERMISSION_DENIED':
      return ErpFailure.permissionDenied;
    case 'NOT_FOUND':
      return ErpFailure.notFound;
    case 'INVALID_ARGUMENT':
      return ErpFailure.invalidArgument;
    case 'FAILED_PRECONDITION':
      return ErpFailure.failedPrecondition;
    case 'RESOURCE_EXHAUSTED':
      return ErpFailure.rateLimited;
    case 'INTERNAL':
    case 'UNAVAILABLE':
    case 'DEADLINE_EXCEEDED':
      return ErpFailure.server;
  }
  if (httpStatus == 401) return ErpFailure.unauthenticated;
  if (httpStatus == 403) return ErpFailure.permissionDenied;
  if (httpStatus == 404) return ErpFailure.notFound;
  if (httpStatus == 400) return ErpFailure.invalidArgument;
  if (httpStatus == 429) return ErpFailure.rateLimited;
  if (httpStatus >= 500) return ErpFailure.server;
  return ErpFailure.unknown;
}

/// Extrait l'objet `error` d'une réponse Google : `{"error": {...}}` ou, pour `runQuery`,
/// `[{"error": {...}}]`.
Map<String, dynamic>? erpErrorBody(Object? json) {
  Object? node = json;
  if (node is List && node.isNotEmpty) node = node.first;
  if (node is Map && node['error'] is Map) {
    return Map<String, dynamic>.from(node['error'] as Map);
  }
  return null;
}
