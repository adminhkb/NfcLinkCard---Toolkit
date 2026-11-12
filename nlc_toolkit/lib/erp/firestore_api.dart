import 'dart:convert';
import 'dart:typed_data';

import 'erp_config.dart';
import 'erp_http.dart';

/// Document Firestore décodé.
class FirestoreDoc {
  const FirestoreDoc({required this.path, required this.data});

  /// Chemin relatif à la racine des documents, par exemple `issuers/abc/badge_sites/xyz`.
  final String path;
  final Map<String, Object?> data;

  String get id => path.substring(path.lastIndexOf('/') + 1);
}

/// Filtre d'une requête sur un seul champ.
class FieldFilter {
  const FieldFilter.equals(this.field, this.value) : op = 'EQUAL';
  const FieldFilter.arrayContains(this.field, this.value)
    : op = 'ARRAY_CONTAINS';

  final String field;
  final String op;
  final Object? value;
}

/// Fournit un jeton d'identité valide pour l'utilisateur connecté.
typedef IdTokenProvider = Future<String> Function();

/// Firestore par son interface REST, en lecture.
class FirestoreApi {
  FirestoreApi(this._config, this._http, this._idToken);

  final ErpConfig _config;
  final ErpHttp _http;
  final IdTokenProvider _idToken;

  /// Lit un document. Renvoie `null` s'il n'existe pas.
  /// [fields] limite la réponse aux champs cités : à utiliser pour les fiches qui portent des secrets.
  Future<FirestoreDoc?> getDocument(String path, {List<String>? fields}) async {
    final url = _documentUrl(path).replace(
      queryParameters: fields == null ? null : {'mask.fieldPaths': fields},
    );
    final response = await _http.get(url, bearer: await _idToken());
    if (response.status == 404) return null;
    _check(response);
    return _decodeDocument(response.json);
  }

  /// Lit tous les documents d'une collection, page après page.
  Future<List<FirestoreDoc>> listDocuments(
    String collectionPath, {
    List<String>? fields,
    int pageSize = 300,
  }) async {
    final documents = <FirestoreDoc>[];
    String? pageToken;
    do {
      final url = _documentUrl(collectionPath).replace(
        queryParameters: {
          'pageSize': '$pageSize',
          'pageToken': ?pageToken,
          'mask.fieldPaths': ?fields,
        },
      );
      final response = await _http.get(url, bearer: await _idToken());
      _check(response);
      final json = response.json;
      if (json is! Map) break;
      for (final item in (json['documents'] as List? ?? const [])) {
        final document = _decodeDocument(item);
        if (document != null) documents.add(document);
      }
      final next = json['nextPageToken'];
      pageToken = next is String && next.isNotEmpty ? next : null;
    } while (pageToken != null);
    return documents;
  }

  /// Interroge la collection [collectionId] située sous [parent] (vide pour une collection racine).
  Future<List<FirestoreDoc>> query(
    String collectionId, {
    String parent = '',
    FieldFilter? where,
    List<String>? fields,
    int? limit,
  }) async {
    final url = Uri.parse(
      '${parent.isEmpty ? _config.documentsRoot : _documentUrl(parent)}:runQuery',
    );
    final body = {
      'structuredQuery': {
        'from': [
          {'collectionId': collectionId},
        ],
        if (where != null)
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': where.field},
              'op': where.op,
              'value': encodeFirestoreValue(where.value),
            },
          },
        if (fields != null)
          'select': {
            'fields': [
              for (final field in fields) {'fieldPath': field},
            ],
          },
        'limit': ?limit,
      },
    };
    final response = await _http.postJson(url, body, bearer: await _idToken());
    _check(response);
    final json = response.json;
    if (json is! List) return const [];
    return [
      for (final row in json)
        if (row is Map && row['document'] != null)
          ?_decodeDocument(row['document']),
    ];
  }

  /// Crée un document dans [collectionPath]. Avec [docId], le document porte cet identifiant
  /// (échoue s'il existe déjà) ; sinon Firestore en attribue un. Renvoie le document créé.
  Future<FirestoreDoc> createDocument(
    String collectionPath,
    Map<String, Object?> fields, {
    String? docId,
  }) async {
    final url = _documentUrl(collectionPath)
        .replace(queryParameters: {'documentId': ?docId});
    final response = await _http.postJson(url, {
      'fields': _encodeFields(fields),
    }, bearer: await _idToken());
    _check(response);
    final doc = _decodeDocument(response.json);
    if (doc == null) {
      throw const ErpException(
        ErpFailure.unknown,
        'Firestore a créé le document sans le renvoyer.',
      );
    }
    return doc;
  }

  /// Écrit [fields] dans le document [path]. Par défaut, seuls les champs fournis sont modifiés
  /// (les autres restent) ; les champs énumérés en plus dans [removeFields] sont effacés.
  Future<FirestoreDoc> patchDocument(
    String path,
    Map<String, Object?> fields, {
    List<String> removeFields = const [],
  }) async {
    final url = _documentUrl(path).replace(
      queryParameters: {
        'updateMask.fieldPaths': [...fields.keys, ...removeFields],
      },
    );
    final response = await _http.patchJson(url, {
      'fields': _encodeFields(fields),
    }, bearer: await _idToken());
    _check(response);
    final doc = _decodeDocument(response.json);
    if (doc == null) {
      throw const ErpException(
        ErpFailure.unknown,
        'Firestore a modifié le document sans le renvoyer.',
      );
    }
    return doc;
  }

  /// Supprime le document [path]. Supprimer un document déjà absent réussit.
  Future<void> deleteDocument(String path) async {
    final response = await _http.delete(
      _documentUrl(path),
      bearer: await _idToken(),
    );
    if (response.status == 404) return;
    _check(response);
  }

  Map<String, Object?> _encodeFields(Map<String, Object?> fields) => {
    for (final entry in fields.entries)
      entry.key: encodeFirestoreValue(entry.value),
  };

  Uri _documentUrl(String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse('${_config.documentsRoot}/$encoded');
  }

  void _check(ErpResponse response) {
    final error = erpErrorBody(response.json);
    if (response.ok && error == null) return;
    final status = error?['status'];
    final message = error?['message'];
    throw ErpException(
      erpFailureFrom(status is String ? status : null, response.status),
      message is String ? message : 'Firestore a répondu ${response.status}.',
      code: status is String ? status : null,
      httpStatus: response.status,
    );
  }

  FirestoreDoc? _decodeDocument(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String) return null;
    const marker = '/documents/';
    final index = name.indexOf(marker);
    final fields = json['fields'];
    return FirestoreDoc(
      path: index < 0 ? name : name.substring(index + marker.length),
      data: fields is Map ? decodeFirestoreFields(fields) : const {},
    );
  }
}

/// Décode le champ `fields` d'un document ou d'une valeur `mapValue`.
Map<String, Object?> decodeFirestoreFields(Map fields) => {
  for (final entry in fields.entries)
    '${entry.key}': decodeFirestoreValue(entry.value),
};

/// Décode une valeur Firestore (`{"stringValue": "…"}`) en valeur Dart.
/// Les dates deviennent des [DateTime] en temps universel.
Object? decodeFirestoreValue(Object? value) {
  if (value is! Map || value.isEmpty) return null;
  final type = value.keys.first;
  final raw = value[type];
  switch (type) {
    case 'nullValue':
      return null;
    case 'booleanValue':
      return raw == true;
    case 'integerValue':
      return raw is int ? raw : int.tryParse('$raw');
    case 'doubleValue':
      if (raw is num) return raw.toDouble();
      // Firestore écrit les valeurs spéciales sous forme de texte.
      return switch ('$raw') {
        'NaN' => double.nan,
        'Infinity' => double.infinity,
        '-Infinity' => double.negativeInfinity,
        _ => double.tryParse('$raw'),
      };
    case 'timestampValue':
      return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    case 'stringValue':
    case 'referenceValue':
      return raw is String ? raw : null;
    case 'bytesValue':
      return raw is String ? base64Decode(raw) : null;
    case 'geoPointValue':
      if (raw is! Map) return null;
      return {
        'latitude': (raw['latitude'] as num?)?.toDouble() ?? 0.0,
        'longitude': (raw['longitude'] as num?)?.toDouble() ?? 0.0,
      };
    case 'arrayValue':
      final values = raw is Map ? raw['values'] : null;
      return [
        if (values is List)
          for (final item in values) decodeFirestoreValue(item),
      ];
    case 'mapValue':
      final fields = raw is Map ? raw['fields'] : null;
      return fields is Map
          ? decodeFirestoreFields(fields)
          : <String, Object?>{};
  }
  return null;
}

/// Encode une valeur Dart en valeur Firestore.
Map<String, Object?> encodeFirestoreValue(Object? value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': '$value'};
  if (value is double) {
    if (value.isNaN) return {'doubleValue': 'NaN'};
    if (value.isInfinite) {
      return {'doubleValue': value.isNegative ? '-Infinity' : 'Infinity'};
    }
    return {'doubleValue': value};
  }
  if (value is String) return {'stringValue': value};
  if (value is DateTime) {
    return {'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is Uint8List) return {'bytesValue': base64Encode(value)};
  if (value is Iterable) {
    return {
      'arrayValue': {'values': value.map(encodeFirestoreValue).toList()},
    };
  }
  if (value is Map) {
    return {
      'mapValue': {
        'fields': {
          for (final entry in value.entries)
            '${entry.key}': encodeFirestoreValue(entry.value),
        },
      },
    };
  }
  throw ArgumentError.value(
    value,
    'value',
    'Type non pris en charge par Firestore',
  );
}
