import 'dart:convert';
import 'dart:typed_data';

import 'erp_config.dart';
import 'erp_http.dart';
import 'firestore_api.dart' show IdTokenProvider;

/// Objet rangé dans Firebase Storage, tel que le serveur le décrit après un téléversement.
class StorageObject {
  const StorageObject({
    required this.path,
    required this.size,
    this.contentType,
  });

  /// Chemin complet de l'objet dans le bucket, par exemple
  /// `issuers/abc/badge_dumps/xyz`.
  final String path;

  /// Taille en octets.
  final int size;
  final String? contentType;
}

/// Firebase Storage par son interface REST (point d'accès `/v0`), authentifié par le jeton
/// d'identité de l'utilisateur connecté. Ce sont les règles de sécurité Storage qui autorisent
/// ou refusent chaque accès — jamais l'application.
class FirebaseStorageApi {
  FirebaseStorageApi(this._config, this._http, this._idToken);

  final ErpConfig _config;
  final ErpHttp _http;
  final IdTokenProvider _idToken;

  /// Téléverse [bytes] à l'emplacement [objectPath] (chemin complet dans le bucket) avec le
  /// type de contenu [contentType]. Renvoie les métadonnées de l'objet créé.
  Future<StorageObject> upload(
    String objectPath,
    Uint8List bytes, {
    required String contentType,
  }) async {
    // `uploadType=media` : le corps est le contenu de l'objet (et non des métadonnées).
    final url = Uri.parse(
      '${_config.storageObjectsRoot}'
      '?uploadType=media&name=${Uri.encodeComponent(objectPath)}',
    );
    final response = await _http.postBytes(
      url,
      bytes,
      headers: {
        'Content-Type': contentType,
        'Authorization': await _authorization(),
      },
    );
    _check(response.status, response.json);
    return _object(
      objectPath,
      response.json,
      fallbackSize: bytes.length,
      fallbackType: contentType,
    );
  }

  /// Télécharge le contenu de l'objet [objectPath]. À utiliser au moment de copier un badge,
  /// sans conserver le fichier localement.
  Future<Uint8List> download(String objectPath) async {
    final url = Uri.parse(
      '${_config.storageObjectsRoot}/${Uri.encodeComponent(objectPath)}?alt=media',
    );
    final response = await _http.getBytes(
      url,
      headers: {'Authorization': await _authorization()},
    );
    if (response.ok) return response.bytes;
    _check(response.status, _tryJson(response.bytes));
    throw ErpException(
      erpFailureFrom(null, response.status),
      'Téléchargement impossible (${response.status}).',
      httpStatus: response.status,
    );
  }

  /// Supprime l'objet [objectPath]. Supprimer un objet déjà absent réussit.
  Future<void> delete(String objectPath) async {
    final url = Uri.parse(
      '${_config.storageObjectsRoot}/${Uri.encodeComponent(objectPath)}',
    );
    final response = await _http.delete(
      url,
      headers: {'Authorization': await _authorization()},
    );
    if (response.status == 404) return;
    _check(response.status, response.json);
  }

  /// Le point d'accès `/v0` attend le schéma « Firebase » suivi du jeton d'identité, à la
  /// différence des API Google (schéma « Bearer »).
  Future<String> _authorization() async => 'Firebase ${await _idToken()}';

  StorageObject _object(
    String path,
    Object? json, {
    required int fallbackSize,
    String? fallbackType,
  }) {
    final map = json is Map ? json : const {};
    return StorageObject(
      path: path,
      size: int.tryParse('${map['size']}') ?? fallbackSize,
      contentType: map['contentType'] is String
          ? map['contentType'] as String
          : fallbackType,
    );
  }

  Object? _tryJson(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  void _check(int status, Object? json) {
    if (status >= 200 && status < 300) return;
    final error = json is Map && json['error'] is Map
        ? json['error'] as Map
        : null;
    final message = error?['message'];
    throw ErpException(
      erpFailureFrom(null, status),
      message is String ? message : 'Storage a répondu $status.',
      httpStatus: status,
    );
  }
}
