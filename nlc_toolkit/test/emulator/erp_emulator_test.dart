// Liaison ERP de bout en bout contre les émulateurs Firebase : vraies règles de sécurité de l'ERP et
// vrai code de ses fonctions de double authentification. Rien ne touche la production.
//
// Ces tests ne tournent que si le banc d'essai est lancé :
//   powershell -ExecutionPolicy Bypass -File tool/erp_emulator/start.ps1 -ErpRepo <dépôt de l'ERP>
//   $env:NLC_ERP_EMULATOR = '1'; flutter test test/emulator
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/badge_dumps.dart';
import 'package:nlc_toolkit/erp/badge_stats.dart';
import 'package:nlc_toolkit/erp/erp_config.dart';
import 'package:nlc_toolkit/erp/erp_directory.dart';
import 'package:nlc_toolkit/erp/erp_http.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/firebase_auth_api.dart';
import 'package:nlc_toolkit/erp/firestore_api.dart';
import 'package:nlc_toolkit/erp/models.dart';
import 'package:nlc_toolkit/erp/secret_store.dart';
import 'package:nlc_toolkit/erp/session.dart';
import 'package:nlc_toolkit/erp/trusted_device.dart';

final _config = ErpConfig.emulator(
  authPort: 19099,
  firestorePort: 18080,
  functionsPort: 15001,
  storagePort: 19199,
);
const _password = 'mot-de-passe-de-test';

/// Accès d'administration à l'émulateur, hors règles de sécurité, pour préparer les données.
class _Admin {
  final client = http.Client();
  static const _owner = {
    'Authorization': 'Bearer owner',
    'Content-Type': 'application/json',
  };

  Future<void> reset() async {
    await client.delete(
      Uri.parse(
        'http://127.0.0.1:18080/emulator/v1/projects/${_config.projectId}/databases/(default)/documents',
      ),
    );
    await client.delete(
      Uri.parse(
        'http://127.0.0.1:19099/emulator/v1/projects/${_config.projectId}/accounts',
      ),
      headers: _owner,
    );
  }

  /// Crée un compte dans l'émulateur d'authentification et renvoie son identifiant.
  Future<String> createUser(String email) async {
    final response = await client.post(
      Uri.parse(
        '${_config.identityBase}/accounts:signUp?key=${_config.apiKey}',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': _password,
        'returnSecureToken': true,
      }),
    );
    final json = jsonDecode(response.body) as Map;
    expect(json['localId'], isA<String>(), reason: response.body);
    return json['localId'] as String;
  }

  Future<void> setDoc(String path, Map<String, Object?> data) async {
    final response = await client.patch(
      Uri.parse('${_config.documentsRoot}/$path'),
      headers: _owner,
      body: jsonEncode({
        'fields': {
          for (final e in data.entries) e.key: encodeFirestoreValue(e.value),
        },
      }),
    );
    expect(response.statusCode, 200, reason: '$path : ${response.body}');
  }

  /// Jeton d'identité d'un compte, pour éprouver directement les règles de sécurité Storage.
  Future<String> idTokenFor(String email) async {
    final response = await client.post(
      Uri.parse(
        '${_config.identityBase}/accounts:signInWithPassword?key=${_config.apiKey}',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': _password,
        'returnSecureToken': true,
      }),
    );
    final json = jsonDecode(response.body) as Map;
    expect(json['idToken'], isA<String>(), reason: response.body);
    return json['idToken'] as String;
  }

  Future<Map<String, Object?>?> getDoc(String path) async {
    final response = await client.get(
      Uri.parse('${_config.documentsRoot}/$path'),
      headers: _owner,
    );
    if (response.statusCode == 404) return null;
    final fields = (jsonDecode(response.body) as Map)['fields'];
    return fields is Map ? decodeFirestoreFields(fields) : {};
  }

  Future<List<Map<String, Object?>>> listDocs(String collection) async {
    final response = await client.get(
      Uri.parse('${_config.documentsRoot}/$collection'),
      headers: _owner,
    );
    final documents =
        (jsonDecode(response.body) as Map)['documents'] as List? ?? const [];
    return [
      for (final doc in documents)
        decodeFirestoreFields((doc as Map)['fields'] as Map? ?? const {}),
    ];
  }
}

/// Compte les renouvellements de jeton demandés au service d'authentification.
class _CountingClient extends http.BaseClient {
  final _inner = http.Client();
  int renewals = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.endsWith('/token')) renewals += 1;
    return _inner.send(request);
  }
}

void main() {
  final enabled = Platform.environment['NLC_ERP_EMULATOR'] == '1';
  final admin = _Admin();

  late String teamUid;
  late String memberUid;
  var clock = DateTime.now();

  ErpServices launch(SecretStore secrets, KeyValueStore local) =>
      ErpServices.create(
        config: _config,
        client: http.Client(),
        secrets: secrets,
        localState: local,
        userAgent: 'NLC Toolkit/test (Windows)',
        now: () => clock,
      );

  setUpAll(() async {
    if (!enabled) return;
    clock = DateTime.now();
    await admin.reset();
    teamUid = await admin.createUser('equipe@nlc.test');
    memberUid = await admin.createUser('gerant@nlc.test');
    await admin.createUser('inconnu@nlc.test');

    await admin.setDoc('users/$teamUid', {
      'isAdmin': true,
      'email': 'equipe@nlc.test',
    });
    await admin.setDoc('issuers/issuerAtelier', {
      'name': 'Atelier Badges',
      'siret': '111 111 111 00011',
      'colorTheme': 'emerald',
      'allowedAdmins': [memberUid],
      // Bloc sensible : l'application ne doit jamais le demander. L'hôte vide évite tout envoi d'e-mail.
      'smtpConfig': {
        'host': '',
        'user': '',
        'pass': 'secret-qui-ne-doit-pas-sortir',
      },
    });
    await admin.setDoc('issuers/issuerAutre', {
      'name': 'Zone Nord',
      'colorTheme': 'indigo',
      'allowedAdmins': <Object?>[],
    });
    await admin.setDoc('issuers/issuerBrouillon', {
      'name': '',
      'allowedAdmins': <Object?>[],
    });

    await admin.setDoc('issuers/issuerAtelier/badge_sites/site1', {
      'name': 'Résidence des Acacias',
      'address': '3 Rue des Acacias',
      'city': 'Orléans',
      'postcode': '45000',
      'lat': 47.9,
      'lng': 1.91,
      'kind': 'residence',
      'units': 40,
      'compatibility': 'ok',
      'doNotProspect': false,
      'createdAt': DateTime.utc(2026, 11, 1, 9),
    });
    await admin.setDoc('issuers/issuerAtelier/badge_sales/sale1', {
      'siteId': 'site1',
      'status': 'rdv',
      'source': 'affiche',
      'customerName': 'Mme Test',
      'customerPhone': '06 00 00 00 00',
      'contactDate': DateTime.utc(2026, 11, 10, 10),
      'appointmentDate': DateTime.utc(2026, 11, 14, 17, 30),
      'quantity': 2,
      'technology': 'mifare_uid',
      'price': 20,
      'paid': false,
    });
    await admin.setDoc('issuers/issuerAtelier/badge_actions/action1', {
      'siteId': 'site1',
      'type': 'affiche',
      'date': DateTime.utc(2026, 11, 2, 12),
      'quantity': 1,
      'cost': 2.5,
    });
    await admin.setDoc('issuers/issuerAutre/badge_sites/siteNord', {
      'name': 'Immeuble du Nord',
    });
  });

  group('émulateurs Firebase', skip: enabled ? false : 'Banc d\'essai non lancé (voir tool/erp_emulator/start.ps1).', () {
    test('équipe : connexion, code par e-mail, appareil mémorisé, puis réouverture sans code', () async {
      final secrets = MemorySecretStore();
      final local = MemoryKeyValueStore();
      final app = launch(secrets, local);
      await app.auth.start();
      await app.auth.signIn('equipe@nlc.test', _password);

      expect(app.auth.stage, AuthStage.secondFactor);
      expect(app.auth.user?.uid, teamUid);
      expect(app.auth.isAdmin, isTrue);
      // Tous les établissements nommés, triés ; le brouillon sans nom est écarté comme dans l'ERP.
      expect(app.auth.issuers.map((i) => i.name), [
        'Atelier Badges',
        'Zone Nord',
      ]);
      expect(app.auth.issuers.first.colorTheme, 'emerald');

      // La fonction de l'ERP enregistre le code puis échoue à l'envoi : aucun serveur d'e-mail ici.
      await app.auth.sendCode();
      expect(app.auth.notice, AuthNotice.unknown);
      expect(app.auth.noticeDetail, contains('SMTP'));
      final pending = await admin.getDoc('users/$teamUid/temp/2fa');
      final code = pending!['code'] as String;
      expect(code, matches(RegExp(r'^\d{6}$')));

      final wrong = code == '000000' ? '111111' : '000000';
      expect(await app.auth.verifyCode(wrong), isFalse);
      expect(app.auth.notice, AuthNotice.invalidCode);
      expect(app.auth.noticeDetail, 'Le code saisi est incorrect.');

      expect(await app.auth.verifyCode(code, rememberDevice: true), isTrue);
      expect(app.auth.stage, AuthStage.ready);
      expect(app.auth.hasTrustedDevice, isTrue);

      // Côté serveur : seule l'empreinte du jeton est gardée, avec le système de l'appareil.
      final devices = await admin.listDocs('users/$teamUid/trusted_devices');
      expect(devices, hasLength(1));
      expect(devices.single['tokenHash'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(devices.single['label'], 'Windows');
      final stored = await TrustedDeviceStore(secrets).load(teamUid);
      expect(
        stored!.expiresAt,
        greaterThan(clock.millisecondsSinceEpoch + 29 * 24 * 3600 * 1000),
      );

      // Réouverture : le serveur reconnaît l'appareil, aucun code n'est demandé.
      final reopened = launch(secrets, local);
      await reopened.auth.start();
      expect(reopened.auth.stage, AuthStage.ready);

      // « Oublier cet appareil » le révoque côté serveur.
      await reopened.auth.forgetThisDevice();
      expect(await admin.listDocs('users/$teamUid/trusted_devices'), isEmpty);
      final again = launch(secrets, local);
      await again.auth.start();
      expect(again.auth.stage, AuthStage.secondFactor);
    });

    test('appareil révoqué depuis l\'ERP : le serveur le refuse et le code est redemandé', () async {
      final secrets = MemorySecretStore();
      final local = MemoryKeyValueStore();
      final app = launch(secrets, local);
      await app.auth.start();
      await app.auth.signIn('equipe@nlc.test', _password);
      await app.auth.sendCode();
      final code =
          (await admin.getDoc('users/$teamUid/temp/2fa'))!['code'] as String;
      expect(await app.auth.verifyCode(code, rememberDevice: true), isTrue);

      // Révocation faite ailleurs (panneau des appareils de l'ERP) : le jeton local existe encore.
      final device = (await TrustedDeviceStore(secrets).load(teamUid))!;
      final revoked = await http.delete(
        Uri.parse(
          '${_config.documentsRoot}/users/$teamUid/trusted_devices/${device.deviceId}',
        ),
        headers: {'Authorization': 'Bearer owner'},
      );
      expect(revoked.statusCode, 200);

      final reopened = launch(secrets, local);
      await reopened.auth.start();
      expect(reopened.auth.stage, AuthStage.secondFactor);
      expect(reopened.auth.trustNotice, TrustNotice.revoked);
      expect(await TrustedDeviceStore(secrets).load(teamUid), isNull);
    });

    test('données Badges lues à travers les règles de sécurité', () async {
      final app = launch(MemorySecretStore(), MemoryKeyValueStore());
      await app.auth.start();
      await app.auth.signIn('equipe@nlc.test', _password);
      await app.auth.sendCode();
      final code =
          (await admin.getDoc('users/$teamUid/temp/2fa'))!['code'] as String;
      await app.auth.verifyCode(code);
      app.auth.selectIssuer('issuerAtelier');
      await app.badges.refresh();

      expect(app.badges.error, isNull);
      final data = app.badges.data!;
      expect(data.sites.single.name, 'Résidence des Acacias');
      expect(data.sites.single.kind, BadgeSiteKind.residence);
      expect(data.sites.single.units, 40);
      expect(data.sites.single.lat, 47.9);
      final sale = data.sales.single;
      expect(sale.status, BadgeSaleStatus.rdv);
      expect(
        sale.appointmentDate,
        DateTime.utc(2026, 11, 14, 17, 30).millisecondsSinceEpoch,
      );
      expect(sale.price, 20);
      expect(sale.paid, isFalse);
      expect(data.actions.single.type, 'affiche');
      final overview = BadgeOverview.compute(
        data,
        clock.millisecondsSinceEpoch,
      );
      expect(overview.upcoming.single.customerName, 'Mme Test');
      expect(overview.sites['site1']!.status, SiteStatus.prospecte);
    });

    test(
      'administrateur d\'un établissement : il ne voit et ne lit que le sien',
      () async {
        final transport = ErpHttp(http.Client());
        final authApi = FirebaseAuthApi(_config, transport);
        final session = SessionManager(authApi, MemorySecretStore());
        await session.open(
          await authApi.signInWithPassword('gerant@nlc.test', _password),
        );
        final firestore = FirestoreApi(
          _config,
          transport,
          session.idTokenForApi,
        );
        final directory = ErpDirectory(firestore);

        final profile = await directory.loadProfile(memberUid);
        expect(profile.allowed, isTrue);
        expect(profile.isAdmin, isFalse);
        expect(profile.issuers.map((i) => i.id), ['issuerAtelier']);

        final own = await directory.loadBadges('issuerAtelier');
        expect(own.sites, hasLength(1));

        // Les règles de l'ERP refusent tout le reste.
        Matcher denied = throwsA(
          isA<ErpException>().having(
            (e) => e.kind,
            'kind',
            ErpFailure.permissionDenied,
          ),
        );
        await expectLater(
          firestore.listDocuments('issuers', fields: Issuer.fields),
          denied,
        );
        await expectLater(directory.loadBadges('issuerAutre'), denied);
        await expectLater(firestore.getDocument('users/$teamUid'), denied);
      },
    );

    test('compte sans droit sur l\'ERP : refusé comme sur le site', () async {
      final secrets = MemorySecretStore();
      final app = launch(secrets, MemoryKeyValueStore());
      await app.auth.start();
      await app.auth.signIn('inconnu@nlc.test', _password);
      expect(app.auth.stage, AuthStage.signedOut);
      expect(app.auth.notice, AuthNotice.notAuthorized);
      expect(secrets.values, isEmpty);
    });

    test('mauvais mot de passe et compte inexistant', () async {
      final app = launch(MemorySecretStore(), MemoryKeyValueStore());
      await app.auth.start();
      await app.auth.signIn('equipe@nlc.test', 'mauvais');
      expect(app.auth.notice, AuthNotice.invalidCredentials);
      await app.auth.signIn('personne@nlc.test', _password);
      expect(app.auth.notice, AuthNotice.invalidCredentials);
      expect(app.auth.stage, AuthStage.signedOut);
    });

    test('le jeton d\'identité se renouvelle et reste accepté', () async {
      final calls = _CountingClient();
      final transport = ErpHttp(calls);
      var now = DateTime.now();
      final authApi = FirebaseAuthApi(_config, transport, now: () => now);
      final session = SessionManager(
        authApi,
        MemorySecretStore(),
        now: () => now,
      );
      await session.open(
        await authApi.signInWithPassword('equipe@nlc.test', _password),
      );
      await session.idToken();
      expect(calls.renewals, 0, reason: 'jeton de la connexion encore valable');

      // Le jeton approche de son expiration : il est renouvelé auprès du service de jetons.
      now = now.add(const Duration(minutes: 58));
      final renewed = await session.idToken();
      expect(calls.renewals, 1);
      expect(renewed.split('.'), hasLength(3), reason: 'jeton au format JWT');
      final firestore = FirestoreApi(_config, transport, session.idTokenForApi);
      expect(
        (await firestore.getDocument('users/$teamUid'))!.data['isAdmin'],
        isTrue,
      );
      expect(
        calls.renewals,
        1,
        reason: 'le nouveau jeton sert aux appels suivants',
      );
    });

    test('la fiche établissement n\'est jamais lue en entier', () async {
      final transport = ErpHttp(http.Client());
      final authApi = FirebaseAuthApi(_config, transport);
      final session = SessionManager(authApi, MemorySecretStore());
      await session.open(
        await authApi.signInWithPassword('equipe@nlc.test', _password),
      );
      final firestore = FirestoreApi(_config, transport, session.idTokenForApi);

      final listed = await firestore.listDocuments(
        'issuers',
        fields: Issuer.fields,
      );
      final queried = await firestore.query(
        'issuers',
        where: FieldFilter.arrayContains('allowedAdmins', memberUid),
        fields: Issuer.fields,
      );
      final single = await firestore.getDocument(
        'issuers/issuerAtelier',
        fields: Issuer.fields,
      );
      for (final doc in [...listed, ...queried, single!]) {
        expect(
          doc.data.keys.toSet().difference(Issuer.fields.toSet()),
          isEmpty,
          reason: doc.path,
        );
      }
      expect(queried.map((d) => d.id), ['issuerAtelier']);
      expect(
        jsonEncode([for (final d in listed) d.data]),
        isNot(contains('secret')),
      );
    });

    test('dump : enregistré dans Storage, rattaché à l\'immeuble, relu puis supprimé', () async {
      final app = launch(MemorySecretStore(), MemoryKeyValueStore());
      await app.auth.start();
      await app.auth.signIn('gerant@nlc.test', _password);
      await app.auth.sendCode();
      final code =
          (await admin.getDoc('users/$memberUid/temp/2fa'))!['code'] as String;
      await app.auth.verifyCode(code);
      app.auth.selectIssuer('issuerAtelier');

      final repo = app.badgeDumps.repo()!;
      final payload = Uint8List.fromList(
        utf8.encode('{"uid":"04AABBCC","blocks":["00","01"]}'),
      );
      final saved = await repo.save(
        NewBadgeDump(
          siteId: 'site1',
          bytes: payload,
          name: 'Acacias — hall',
          technology: BadgeTech.mifareUid,
          uid: '04AABBCC',
          tagType: 1001,
        ),
      );
      expect(saved.createdBy, memberUid);
      expect(
        saved.storagePath,
        'issuers/issuerAtelier/badge_dumps/${saved.id}',
      );

      final listed = await repo.listForSite('site1');
      expect(listed.map((d) => d.id), contains(saved.id));

      // Le contenu se relit à travers les règles Storage : le schéma « Firebase » est accepté.
      expect(await repo.fetch(saved), equals(payload));

      // La référence est bien un document Firestore rangé sous l'établissement.
      final doc = await admin.getDoc(
        'issuers/issuerAtelier/badge_dumps/${saved.id}',
      );
      expect(doc!['siteId'], 'site1');
      expect(doc['createdBy'], memberUid);

      await repo.delete(saved);
      expect(await repo.listForSite('site1'), isEmpty);
      await expectLater(
        repo.fetch(saved),
        throwsA(
          isA<ErpException>().having(
            (e) => e.kind,
            'kind',
            ErpFailure.notFound,
          ),
        ),
      );
    });

    test('dump : les règles Storage cloisonnent par établissement et limitent la taille', () async {
      final token = await admin.idTokenFor('gerant@nlc.test');
      Future<int> upload(String path, {List<int>? body}) async {
        final response = await http.post(
          Uri.parse(
            '${_config.storageObjectsRoot}'
            '?uploadType=media&name=${Uri.encodeComponent(path)}',
          ),
          headers: {
            'Authorization': 'Firebase $token',
            'Content-Type': 'application/octet-stream',
          },
          body: body ?? utf8.encode('{"x":1}'),
        );
        return response.statusCode;
      }

      // Son propre établissement : autorisé.
      expect(await upload('issuers/issuerAtelier/badge_dumps/controle'), 200);
      // Un établissement qu'il n'administre pas : refusé.
      expect(await upload('issuers/issuerAutre/badge_dumps/controle'), 403);
      // Un fichier au-delà de la limite : refusé.
      expect(
        await upload(
          'issuers/issuerAtelier/badge_dumps/controle2',
          body: List.filled(2 * 1024 * 1024, 48),
        ),
        403,
      );
    });
  });
}
