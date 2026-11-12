// Faux ERP en mémoire pour les tests et le mode démonstration.
//
// Il répond comme les services Firebase (Auth, Firestore, fonctions appelables) à travers un client
// HTTP factice : le code de l'application est exercé tel quel, sans aucun accès au réseau ni à la
// base de production. Toutes les données sont inventées.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../erp_config.dart';
import '../firestore_api.dart';

class DemoBackend {
  DemoBackend({DateTime Function()? now, bool seed = true})
    : _now = now ?? DateTime.now {
    if (seed) seedSampleData();
  }

  final DateTime Function() _now;

  static const projectId = 'demo-nlc';
  static const email = 'demo@nlc.test';
  static const password = 'demo-nlc';
  static const uid = 'demoUser0000000000000000AAAA';
  static const validCode = '123456';
  static const mainIssuerId = 'demoIssuer0000000001';

  /// Simule une coupure réseau : chaque appel échoue comme si le serveur était injoignable.
  bool offline = false;

  /// Le compte a été désactivé : le renouvellement de session est refusé.
  bool accountDisabled = false;

  /// Documents Firestore : chemin → champs.
  final Map<String, Map<String, Object?>> documents = {};

  /// Objets Storage en mémoire : chemin dans le bucket → contenu et type.
  final Map<String, ({List<int> bytes, String contentType})> storageObjects =
      {};

  /// Appareils mémorisés : identifiant → jeton et expiration.
  final Map<String, ({String token, int expiresAt})> trustedDevices = {};

  /// Fonctions qui répondent par une erreur interne, pour simuler une panne passagère.
  final Set<String> brokenFunctions = {};

  /// Journal des appels reçus (« POST verifyAdmin2FACode »), pour les tests.
  final List<String> calls = [];
  int codesSent = 0;

  /// Nombre de fiches établissement servies en entier, secrets compris : doit rester à zéro.
  int unmaskedIssuerReads = 0;
  int _tokenSerial = 0;
  int _deviceSerial = 0;
  int _docSerial = 0;
  String? _validIdToken;

  ErpConfig get config => ErpConfig.emulator(projectId: projectId);

  http.Client get client => MockClient(_handle);

  /* ─────────────── Données d'exemple ─────────────── */

  /// Un compte de l'équipe, deux établissements et une tournée fictive autour d'Orléans.
  void seedSampleData() {
    final now = _now();
    DateTime at(int days, int hour, [int minute = 0]) =>
        DateTime(now.year, now.month, now.day + days, hour, minute);
    DateTime noon(int days) => at(days, 12);

    documents['users/$uid'] = {'isAdmin': true, 'email': email};
    documents['issuers/$mainIssuerId'] = {
      'name': 'Société Exemple (démonstration)',
      'siret': '000 000 000 00000',
      'colorTheme': 'indigo',
      'allowedAdmins': <Object?>[],
      'smtpConfig': {'host': 'ne-doit-jamais-etre-lu', 'pass': 'secret'},
    };
    documents['issuers/demoIssuer0000000002'] = {
      'name': 'Atelier Badges (démonstration)',
      'siret': '',
      'colorTheme': 'emerald',
      'allowedAdmins': <Object?>[],
    };

    void site(String id, Map<String, Object?> data) =>
        documents['issuers/$mainIssuerId/badge_sites/$id'] = data;
    void sale(String id, Map<String, Object?> data) =>
        documents['issuers/$mainIssuerId/badge_sales/$id'] = data;
    void action(String id, Map<String, Object?> data) =>
        documents['issuers/$mainIssuerId/badge_actions/$id'] = data;

    site('siteTilleuls', {
      'name': 'Résidence Les Tilleuls',
      'address': '12 Rue de Bourgogne',
      'city': 'Orléans',
      'postcode': '45000',
      'lat': 47.9012,
      'lng': 1.9128,
      'kind': 'residence',
      'units': 48,
      'accessSystem': 'Intratone',
      'compatibility': 'ok',
      'doNotProspect': false,
      'notes': '',
    });
    site('siteJeanne', {
      'name': "Immeuble Jeanne d'Arc",
      'address': '4 Place du Martroi',
      'city': 'Orléans',
      'postcode': '45000',
      'lat': 47.9027,
      'lng': 1.9042,
      'kind': 'immeuble',
      'units': 22,
      'accessSystem': 'Vigik',
      'compatibility': 'partielle',
      'doNotProspect': false,
    });
    site('siteSaintMarc', {
      'name': 'Le Clos Saint-Marc',
      'address': '31 Rue Saint-Marc',
      'city': 'Orléans',
      'postcode': '45000',
      'lat': 47.9051,
      'lng': 1.9211,
      'kind': 'residence',
      'units': 64,
      'accessSystem': 'Hexact',
      'compatibility': 'ok',
    });
    site('siteParking', {
      'name': 'Parking République',
      'address': '2 Rue de la République',
      'city': 'Orléans',
      'postcode': '45000',
      'lat': 47.9038,
      'lng': 1.9069,
      'kind': 'parking',
      'compatibility': 'inconnue',
    });
    site('siteParc', {
      'name': 'Résidence du Parc',
      'address': '18 Avenue Dauphine',
      'city': 'Orléans',
      'postcode': '45100',
      'lat': 47.8942,
      'lng': 1.9004,
      'kind': 'residence',
      'units': 30,
      'compatibility': 'ko',
      'doNotProspect': true,
    });
    site('siteBoulangerie', {
      'name': 'Boulangerie du Centre',
      'address': '7 Rue Royale',
      'city': 'Orléans',
      'postcode': '45000',
      'lat': 47.9006,
      'lng': 1.9048,
      'kind': 'lieu_passage',
      'compatibility': 'inconnue',
    });

    action('actionAffiche1', {
      'siteId': 'siteTilleuls',
      'type': 'affiche',
      'date': noon(-21),
      'quantity': 1,
      'cost': 2.5,
    });
    action('actionAffiche2', {
      'siteId': 'siteSaintMarc',
      'type': 'affiche',
      'date': noon(-12),
      'quantity': 2,
      'cost': 5,
    });
    action('actionFlyers', {
      'siteId': 'siteJeanne',
      'type': 'flyer_bal',
      'date': noon(-6),
      'quantity': 22,
      'cost': 4,
    });
    action('actionVitrine', {
      'siteId': 'siteBoulangerie',
      'type': 'affiche',
      'date': noon(-9),
      'quantity': 1,
      'cost': 2.5,
    });

    sale('saleRdvToday', {
      'siteId': 'siteSaintMarc',
      'status': 'rdv',
      'source': 'affiche',
      'customerName': 'Mme Camille Lefèvre',
      'customerPhone': '06 00 00 00 01',
      'customerDetail': 'Bât. B, 3e étage',
      'contactDate': at(-1, 17, 20),
      'appointmentDate': at(0, 18, 30),
      'quantity': 2,
      'technology': 'mifare_uid',
      'price': 20,
      'paid': false,
    });
    sale('saleRdvTomorrow', {
      'siteId': 'siteTilleuls',
      'status': 'rdv',
      'source': 'lieu_passage',
      'sourceSiteId': 'siteBoulangerie',
      'customerName': 'M. Hugo Marchand',
      'customerPhone': '06 00 00 00 02',
      'customerDetail': 'Appartement 12',
      'contactDate': at(0, 9, 5),
      'appointmentDate': at(1, 10, 0),
      'quantity': 4,
      'technology': 'mifare_uid',
      'price': 35,
      'paid': false,
      'atHome': true,
    });
    sale('saleRdvLate', {
      'siteId': 'siteJeanne',
      'status': 'rdv',
      'source': 'flyer_bal',
      'customerName': 'Mme Inès Roussel',
      'customerPhone': '06 00 00 00 03',
      'customerDetail': '2e étage gauche',
      'contactDate': at(-3, 11, 0),
      'appointmentDate': at(-1, 14, 0),
      'quantity': 1,
      'technology': 'mifare_cuid',
      'price': 10,
      'paid': false,
    });
    sale('saleRdvWeek', {
      'siteId': 'siteSaintMarc',
      'status': 'rdv',
      'source': 'bouche_a_oreille',
      'customerName': 'M. Théo Garnier',
      'customerPhone': '',
      'customerDetail': 'Bât. A, rez-de-chaussée',
      'contactDate': at(-1, 19, 40),
      'appointmentDate': at(4, 17, 0),
      'quantity': 1,
      'technology': 'mifare_uid',
      'price': 10,
      'paid': false,
    });
    sale('saleDemande', {
      'siteId': 'siteParking',
      'status': 'demande',
      'source': 'internet',
      'customerName': 'Mme Léa Fontaine',
      'customerPhone': '06 00 00 00 04',
      'contactDate': at(0, 8, 15),
      'quantity': 2,
      'technology': 'em_t5577',
      'price': 20,
      'paid': false,
    });
    sale('saleCopie1', {
      'siteId': 'siteTilleuls',
      'status': 'copie',
      'source': 'affiche',
      'customerName': 'M. Louis Perrin',
      'contactDate': at(-15, 18, 0),
      'copyDate': noon(-13),
      'quantity': 4,
      'technology': 'mifare_uid',
      'price': 35,
      'paid': true,
    });
    sale('saleCopie2', {
      'siteId': 'siteTilleuls',
      'status': 'copie',
      'source': 'affiche',
      'customerName': 'Mme Zoé Lambert',
      'contactDate': at(-8, 12, 30),
      'copyDate': noon(-7),
      'quantity': 2,
      'technology': 'mifare_uid',
      'price': 20,
      'paid': true,
    });
    sale('saleCopie3', {
      'siteId': 'siteSaintMarc',
      'status': 'copie',
      'source': 'affiche',
      'customerName': 'M. Noé Chevalier',
      'contactDate': at(-5, 10, 0),
      'copyDate': noon(-4),
      'quantity': 1,
      'technology': 'mifare_uid',
      'price': 10,
      'paid': true,
    });
    sale('saleAnnule', {
      'siteId': 'siteParc',
      'status': 'annule',
      'source': 'porte_a_porte',
      'customerName': 'M. Paul Renard',
      'contactDate': at(-10, 16, 0),
      'quantity': 1,
      'failedCount': 1,
      'technology': 'mifare_cuid',
      'price': 0,
      'cancelReason': 'Badge non copiable',
    });

    // Un dump déjà enregistré sur un immeuble (référence Firestore + fichier dans Storage).
    const dumpPath = 'issuers/$mainIssuerId/badge_dumps/dumpTilleuls00000001';
    documents[dumpPath] = {
      'siteId': 'siteTilleuls',
      'storagePath': dumpPath,
      'name': 'Les Tilleuls — hall A',
      'technology': 'mifare_uid',
      'uid': '04A1B2C3',
      'tagType': 1001,
      'byteSize': 64,
      'createdAt': noon(-13),
      'createdBy': uid,
    };
    storageObjects[dumpPath] = (
      bytes: utf8.encode('{"demo":"dump"}'),
      contentType: 'application/json',
    );
  }

  /* ─────────────── Aiguillage ─────────────── */

  Future<http.Response> _handle(http.Request request) async {
    if (offline) {
      throw http.ClientException('Réseau coupé (simulation)', request.url);
    }
    final path = request.url.path;
    calls.add('${request.method} ${path.substring(path.lastIndexOf('/') + 1)}');

    if (path.endsWith('/accounts:signInWithPassword')) return _signIn(request);
    if (path.endsWith('/securetoken.googleapis.com/v1/token')) {
      return _refresh(request);
    }

    if (path.contains('/v0/b/')) return _storage(request);

    const marker = '/databases/(default)/documents';
    final index = path.indexOf(marker);
    if (index >= 0) {
      if (!_authorized(request)) {
        return _error(401, 'UNAUTHENTICATED', 'Jeton absent ou expiré.');
      }
      final rest = path.substring(index + marker.length);
      if (rest.endsWith(':runQuery')) {
        return _runQuery(
          request,
          _trim(rest.substring(0, rest.length - ':runQuery'.length)),
        );
      }
      final target = _trim(rest);
      // Un chemin de document a un nombre pair de segments, une collection un nombre impair.
      return switch (request.method) {
        'POST' => _createDocument(request, target),
        'PATCH' => _patchDocument(request, target),
        'DELETE' => _deleteDocument(target),
        _ =>
          target.split('/').length.isEven
              ? _getDocument(request, target)
              : _list(request, target),
      };
    }

    final functionPrefix = '/$projectId/us-central1/';
    if (path.startsWith(functionPrefix)) {
      if (!_authorized(request)) {
        return _error(401, 'UNAUTHENTICATED', 'Vous devez être connecté.');
      }
      return _callable(path.substring(functionPrefix.length), request);
    }
    return _error(404, 'NOT_FOUND', 'Adresse inconnue : $path');
  }

  String _trim(String path) =>
      Uri.decodeComponent(path).replaceAll(RegExp(r'^/+|/+$'), '');

  bool _authorized(http.Request request) =>
      _validIdToken != null &&
      request.headers['Authorization'] == 'Bearer $_validIdToken';

  http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _error(int status, String code, String message) => _json({
    'error': {'code': status, 'message': message, 'status': code},
  }, status);

  /* ─────────────── Firebase Auth ─────────────── */

  String _issueIdToken() => _validIdToken = 'demo-id-token-${++_tokenSerial}';

  http.Response _signIn(http.Request request) {
    final body = jsonDecode(request.body) as Map;
    if (body['email'] != email || body['password'] != password) {
      return _error(400, 'INVALID_ARGUMENT', 'INVALID_LOGIN_CREDENTIALS');
    }
    if (accountDisabled) {
      return _error(400, 'INVALID_ARGUMENT', 'USER_DISABLED');
    }
    return _json({
      'kind': 'identitytoolkit#VerifyPasswordResponse',
      'localId': uid,
      'email': email,
      'displayName': '',
      'idToken': _issueIdToken(),
      'registered': true,
      'refreshToken': 'demo-refresh-token',
      'expiresIn': '3600',
    });
  }

  http.Response _refresh(http.Request request) {
    final fields = request.bodyFields;
    if (accountDisabled) {
      return _error(400, 'INVALID_ARGUMENT', 'USER_DISABLED');
    }
    if (fields['grant_type'] != 'refresh_token' ||
        fields['refresh_token'] != 'demo-refresh-token') {
      return _error(400, 'INVALID_ARGUMENT', 'INVALID_REFRESH_TOKEN');
    }
    return _json({
      'access_token': _issueIdToken(),
      'expires_in': '3600',
      'token_type': 'Bearer',
      'refresh_token': 'demo-refresh-token',
      'id_token': _validIdToken,
      'user_id': uid,
      'project_id': '000000000000',
    });
  }

  /* ─────────────── Firestore ─────────────── */

  bool get _isTeamMember => documents['users/$uid']?['isAdmin'] == true;

  Map<String, Object?> _encode(
    String path,
    Map<String, Object?> data,
    Iterable<String>? mask,
  ) {
    if (mask == null &&
        path.startsWith('issuers/') &&
        path.split('/').length == 2) {
      unmaskedIssuerReads += 1;
    }
    return _document(path, data, mask);
  }

  Map<String, Object?> _document(
    String path,
    Map<String, Object?> data,
    Iterable<String>? mask,
  ) => {
    'name': 'projects/$projectId/databases/(default)/documents/$path',
    'fields': {
      for (final entry in data.entries)
        if (mask == null || mask.contains(entry.key))
          entry.key: encodeFirestoreValue(entry.value),
    },
    'createTime': '2026-01-01T00:00:00.000000Z',
    'updateTime': '2026-01-01T00:00:00.000000Z',
  };

  Iterable<MapEntry<String, Map<String, Object?>>> _children(
    String collectionPath,
  ) {
    final prefix = '$collectionPath/';
    return documents.entries.where(
      (entry) =>
          entry.key.startsWith(prefix) &&
          !entry.key.substring(prefix.length).contains('/'),
    );
  }

  http.Response _getDocument(http.Request request, String path) {
    final data = documents[path];
    if (data == null) {
      return _error(404, 'NOT_FOUND', 'Document "$path" not found.');
    }
    return _json(
      _encode(path, data, request.url.queryParametersAll['mask.fieldPaths']),
    );
  }

  http.Response _list(http.Request request, String collectionPath) {
    // Comme les règles de l'ERP : seule l'équipe peut lister tous les établissements.
    if (collectionPath == 'issuers' && !_isTeamMember) {
      return _error(
        403,
        'PERMISSION_DENIED',
        'Missing or insufficient permissions.',
      );
    }
    final mask = request.url.queryParametersAll['mask.fieldPaths'];
    final children = _children(collectionPath).toList();
    if (children.isEmpty) return _json(<String, Object?>{});
    return _json({
      'documents': [
        for (final entry in children) _encode(entry.key, entry.value, mask),
      ],
    });
  }

  http.Response _runQuery(http.Request request, String parent) {
    final query = (jsonDecode(request.body) as Map)['structuredQuery'] as Map;
    final collectionId =
        ((query['from'] as List).first as Map)['collectionId'] as String;
    final collectionPath = parent.isEmpty
        ? collectionId
        : '$parent/$collectionId';
    final filter = (query['where'] as Map?)?['fieldFilter'] as Map?;
    final select = ((query['select'] as Map?)?['fields'] as List?)
        ?.map((field) => (field as Map)['fieldPath'] as String)
        .toList();

    bool matches(Map<String, Object?> data) {
      if (filter == null) return true;
      final field = (filter['field'] as Map)['fieldPath'] as String;
      final expected = decodeFirestoreValue(filter['value']);
      final actual = data[field];
      return switch (filter['op']) {
        'EQUAL' => actual == expected,
        'ARRAY_CONTAINS' => actual is List && actual.contains(expected),
        _ => false,
      };
    }

    final rows = [
      for (final entry in _children(collectionPath))
        if (matches(entry.value))
          {
            'document': _encode(entry.key, entry.value, select),
            'readTime': '2026-01-01T00:00:00.000000Z',
          },
    ];
    return _json(
      rows.isEmpty
          ? [
              {'readTime': '2026-01-01T00:00:00.000000Z'},
            ]
          : rows,
    );
  }

  Map<String, Object?> _decodeFields(Object? fields) => {
    if (fields is Map)
      for (final entry in fields.entries)
        '${entry.key}': decodeFirestoreValue(entry.value),
  };

  http.Response _createDocument(http.Request request, String collectionPath) {
    final id =
        request.url.queryParameters['documentId'] ?? 'demoDoc${++_docSerial}';
    final path = '$collectionPath/$id';
    if (documents.containsKey(path)) {
      return _error(409, 'ALREADY_EXISTS', 'Document "$path" existe déjà.');
    }
    final fields = _decodeFields((jsonDecode(request.body) as Map)['fields']);
    documents[path] = fields;
    return _json(_document(path, fields, null));
  }

  http.Response _patchDocument(http.Request request, String path) {
    // Seuls les champs fournis sont modifiés ; les autres restent.
    final incoming = _decodeFields((jsonDecode(request.body) as Map)['fields']);
    documents[path] = {...?documents[path], ...incoming};
    return _json(_document(path, documents[path]!, null));
  }

  http.Response _deleteDocument(String path) {
    documents.remove(path);
    return _json(<String, Object?>{});
  }

  /* ─────────────── Firebase Storage ─────────────── */

  bool _storageAuthorized(http.Request request) =>
      _validIdToken != null &&
      request.headers['Authorization'] == 'Firebase $_validIdToken';

  Map<String, Object?> _storageMeta(String objectPath) {
    final object = storageObjects[objectPath];
    return {
      'name': objectPath,
      'bucket': config.storageBucket,
      'size': '${object?.bytes.length ?? 0}',
      'contentType': object?.contentType ?? 'application/octet-stream',
    };
  }

  http.Response _storage(http.Request request) {
    if (!_storageAuthorized(request)) {
      return _error(401, 'UNAUTHENTICATED', 'Jeton Storage absent ou refusé.');
    }
    final path = request.url.path;
    // Un objet est désigné par `.../o/<chemin encodé>` ; le téléversement vise `.../o?name=…`.
    final objectPath = path.contains('/o/')
        ? Uri.decodeComponent(path.substring(path.indexOf('/o/') + 3))
        : null;
    switch (request.method) {
      case 'POST':
        final name = request.url.queryParameters['name'];
        if (name == null) {
          return _error(
            400,
            'INVALID_ARGUMENT',
            'Paramètre « name » manquant.',
          );
        }
        storageObjects[name] = (
          bytes: request.bodyBytes,
          contentType:
              request.headers['content-type'] ?? 'application/octet-stream',
        );
        return _json(_storageMeta(name));
      case 'GET':
        if (objectPath == null || !storageObjects.containsKey(objectPath)) {
          return _error(404, 'NOT_FOUND', 'Objet introuvable.');
        }
        if (request.url.queryParameters['alt'] == 'media') {
          final object = storageObjects[objectPath]!;
          return http.Response.bytes(
            object.bytes,
            200,
            headers: {'content-type': object.contentType},
          );
        }
        return _json(_storageMeta(objectPath));
      case 'DELETE':
        if (objectPath == null || storageObjects.remove(objectPath) == null) {
          return _error(404, 'NOT_FOUND', 'Objet introuvable.');
        }
        return _json(<String, Object?>{});
    }
    return _error(405, 'INVALID_ARGUMENT', 'Méthode non gérée par Storage.');
  }

  /* ─────────────── Fonctions appelables ─────────────── */

  http.Response _callable(String name, http.Request request) {
    final data = (jsonDecode(request.body) as Map)['data'];
    final input = data is Map ? data : const {};
    final now = _now().millisecondsSinceEpoch;
    if (brokenFunctions.contains(name)) {
      return _error(500, 'INTERNAL', 'INTERNAL');
    }
    switch (name) {
      case 'sendAdmin2FACode':
        // Même contrôle que la fonction de l'ERP : établissement, administrateur autorisé ou équipe.
        final allowed =
            _isTeamMember ||
            documents.containsKey('issuers/$uid') ||
            _children('issuers').any((issuer) {
              final admins = issuer.value['allowedAdmins'];
              return admins is List && admins.contains(uid);
            });
        if (!allowed) {
          return _error(
            403,
            'PERMISSION_DENIED',
            "Ce compte n'est pas autorisé à accéder à l'application.",
          );
        }
        codesSent += 1;
        return _json({
          'result': {'success': true},
        });

      case 'verifyAdmin2FACode':
        if ('${input['code']}'.trim() != validCode) {
          return _json({
            'result': {
              'success': false,
              'error': 'Le code saisi est incorrect.',
            },
          });
        }
        if (input['rememberDevice'] != true) {
          return _json({
            'result': {'success': true},
          });
        }
        trustedDevices.remove(input['replaceDeviceId']);
        final deviceId = 'demoDevice${'${++_deviceSerial}'.padLeft(10, '0')}';
        final token = 'demoDeviceToken${'$_deviceSerial'.padLeft(28, '0')}';
        final expiresAt = now + 30 * 24 * 3600 * 1000;
        trustedDevices[deviceId] = (token: token, expiresAt: expiresAt);
        return _json({
          'result': {
            'success': true,
            'trustedDevice': {
              'deviceId': deviceId,
              'token': token,
              'expiresAt': expiresAt,
            },
          },
        });

      case 'checkTrustedDevice':
        final known = trustedDevices[input['deviceId']];
        if (known == null || known.token != input['token']) {
          return _json({
            'result': {'trusted': false, 'reason': 'unknown'},
          });
        }
        if (known.expiresAt <= now) {
          trustedDevices.remove(input['deviceId']);
          return _json({
            'result': {'trusted': false, 'reason': 'expired'},
          });
        }
        return _json({
          'result': {'trusted': true, 'expiresAt': known.expiresAt},
        });

      case 'revokeTrustedDevices':
        final removed = trustedDevices.remove(input['deviceId']) != null;
        return _json({
          'result': {'revoked': removed ? 1 : 0},
        });
    }
    return _error(404, 'NOT_FOUND', 'Fonction inconnue : $name');
  }
}
