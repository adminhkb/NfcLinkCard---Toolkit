// Lecture des données de l'ERP : valeurs Firestore, valeurs par défaut, statut des immeubles.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/badge_stats.dart';
import 'package:nlc_toolkit/erp/demo/demo_backend.dart';
import 'package:nlc_toolkit/erp/erp_http.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/firebase_auth_api.dart';
import 'package:nlc_toolkit/erp/firestore_api.dart';
import 'package:nlc_toolkit/erp/models.dart';
import 'package:nlc_toolkit/erp/secret_store.dart';
import 'package:nlc_toolkit/erp/trusted_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('valeurs Firestore', () {
    test('décodage des types écrits par l\'ERP', () {
      // Forme exacte d'une réponse de l'API REST : les entiers arrivent sous forme de texte.
      final fields = jsonDecode('''
      {
        "name": {"stringValue": "Résidence Les Tilleuls"},
        "units": {"integerValue": "48"},
        "lat": {"doubleValue": 47.9012},
        "doNotProspect": {"booleanValue": false},
        "notes": {"nullValue": null},
        "createdAt": {"timestampValue": "2026-11-12T13:30:00.123456Z"},
        "allowedAdmins": {"arrayValue": {"values": [{"stringValue": "a"}, {"stringValue": "b"}]}},
        "vide": {"arrayValue": {}},
        "smtp": {"mapValue": {"fields": {"port": {"integerValue": "587"}}}}
      }''') as Map;
      final data = decodeFirestoreFields(fields);
      expect(data['name'], 'Résidence Les Tilleuls');
      expect(data['units'], 48);
      expect(data['lat'], 47.9012);
      expect(data['doNotProspect'], false);
      expect(data.containsKey('notes'), isTrue);
      expect(data['notes'], isNull);
      expect(
        data['createdAt'],
        DateTime.utc(2026, 11, 12, 13, 30, 0, 123, 456),
      );
      expect(data['allowedAdmins'], ['a', 'b']);
      expect(data['vide'], isEmpty);
      expect(data['smtp'], {'port': 587});
    });

    test('aller-retour encodage / décodage', () {
      final values = <Object?>[
        null,
        true,
        42,
        -7,
        3.5,
        'texte accentué é€',
        DateTime.utc(2026, 1, 2, 3, 4, 5),
        Uint8List.fromList([0, 1, 254, 255]),
        ['a', 1, null],
        {
          'k': 'v',
          'n': {'x': 1},
        },
      ];
      for (final value in values) {
        expect(
          decodeFirestoreValue(encodeFirestoreValue(value)),
          value,
          reason: '$value',
        );
      }
      expect(encodeFirestoreValue(12), {'integerValue': '12'});
      expect(encodeFirestoreValue(12.0), {'doubleValue': 12.0});
    });
  });

  group('fiches Badges', () {
    final now = DateTime(2026, 11, 12, 14).millisecondsSinceEpoch;

    test('une copie incomplète reçoit les mêmes valeurs par défaut que dans l\'ERP', () {
      final sale = BadgeSale.fromDoc(
        const FirestoreDoc(path: 'issuers/i/badge_sales/s1', data: {}),
        now: now,
      );
      expect(sale.id, 's1');
      expect(sale.status, BadgeSaleStatus.copie);
      expect(sale.source, 'autre');
      expect(sale.siteId, isNull);
      expect(sale.quantity, 1);
      expect(sale.failedCount, 0);
      expect(sale.technology, BadgeTech.mifareUid);
      expect(sale.paid, isTrue);
      expect(sale.atHome, isFalse);
      expect(sale.contactDate, now);
    });

    test('dates : horodatage Firestore, millisecondes ou texte', () {
      final when = DateTime.utc(2026, 11, 14, 17, 30);
      for (final stored in <Object>[
        when,
        when.millisecondsSinceEpoch,
        when.toIso8601String(),
      ]) {
        final sale = BadgeSale.fromDoc(
          FirestoreDoc(
            path: 'issuers/i/badge_sales/s',
            data: {
              'status': 'rdv',
              'appointmentDate': stored,
              'contactDate': 1000,
            },
          ),
          now: now,
        );
        expect(
          sale.appointmentDate,
          when.millisecondsSinceEpoch,
          reason: '${stored.runtimeType}',
        );
        expect(sale.date, when.millisecondsSinceEpoch);
      }
    });

    test('un immeuble sans position ni type reste lisible', () {
      final site = BadgeSite.fromDoc(
        const FirestoreDoc(
          path: 'issuers/i/badge_sites/x',
          data: {
            'name': 'Sans adresse',
            'kind': 'inconnu',
            'lat': 'abc',
            'units': 12.0,
          },
        ),
      );
      expect(site.kind, BadgeSiteKind.immeuble);
      expect(site.hasPosition, isFalse);
      expect(site.units, 12);
      expect(site.compatibility, BadgeCompatibility.inconnue);
    });

    test('l\'ancien type d\'action « gardien » devient « autre »', () {
      final action = BadgeAction.fromDoc(
        const FirestoreDoc(
          path: 'issuers/i/badge_actions/a',
          data: {'type': 'gardien', 'siteId': 's'},
        ),
        now: now,
      );
      expect(action.type, 'autre');
      expect(action.quantity, 1);
    });
  });

  group('statut des immeubles', () {
    BadgeSite site(
      String id, {
      bool blocked = false,
      BadgeSiteKind kind = BadgeSiteKind.immeuble,
    }) => BadgeSite(id: id, name: id, kind: kind, doNotProspect: blocked);
    BadgeSale sale(
      String id,
      String? siteId,
      BadgeSaleStatus status, {
      int quantity = 1,
      String source = 'affiche',
      String? from,
    }) => BadgeSale(
      id: id,
      siteId: siteId,
      status: status,
      contactDate: 0,
      quantity: quantity,
      source: source,
      sourceSiteId: from,
    );

    test('à prospecter, prospecté, clients, bloqué', () {
      final actions = [
        const BadgeAction(id: 'a', siteId: 'p', type: 'affiche', date: 0),
      ];
      final sales = [
        sale('1', 'c', BadgeSaleStatus.copie, quantity: 3),
        sale('2', 'c', BadgeSaleStatus.rdv),
        sale('3', 'b', BadgeSaleStatus.copie),
      ];
      expect(
        computeSiteSummary(site('n'), actions, sales).status,
        SiteStatus.nouveau,
      );
      expect(
        computeSiteSummary(site('p'), actions, sales).status,
        SiteStatus.prospecte,
      );
      final client = computeSiteSummary(site('c'), actions, sales);
      expect(client.status, SiteStatus.client);
      expect(client.badges, 3);
      expect(client.contacts, 2);
      expect(client.openLeads, 1);
      // Un immeuble « ne pas prospecter » reste bloqué même s'il a déjà des clients.
      expect(
        computeSiteSummary(site('b', blocked: true), actions, sales).status,
        SiteStatus.bloque,
      );
    });

    test('un lieu de passage compte les copies qu\'il a amenées', () {
      final place = site('lieu', kind: BadgeSiteKind.lieuPassage);
      final sales = [
        sale(
          '1',
          'immeuble',
          BadgeSaleStatus.copie,
          quantity: 4,
          source: 'lieu_passage',
          from: 'lieu',
        ),
        sale(
          '2',
          'immeuble',
          BadgeSaleStatus.demande,
          source: 'lieu_passage',
          from: 'lieu',
        ),
      ];
      final summary = computeSiteSummary(place, const [], sales);
      expect(summary.status, SiteStatus.client);
      expect(
        summary.contacts,
        0,
        reason: 'les copies restent rangées dans l\'immeuble du client',
      );
      expect(summary.broughtContacts, 2);
      expect(summary.broughtBadges, 4);
    });
  });

  test('chargement des données de démonstration de bout en bout', () async {
    final clock = DateTime(2026, 11, 12, 14, 30);
    final backend = DemoBackend(now: () => clock);
    final app = ErpServices.create(
      config: backend.config,
      client: backend.client,
      secrets: MemorySecretStore(),
      localState: MemoryKeyValueStore(),
      now: () => clock,
    );
    await app.auth.start();
    await app.auth.signIn(DemoBackend.email, DemoBackend.password);
    await app.auth.verifyCode(DemoBackend.validCode);
    app.auth.selectIssuer(DemoBackend.mainIssuerId);
    await app.badges.refresh();

    final data = app.badges.data!;
    final overview = app.badges.overview!;
    expect(app.badges.error, isNull);
    expect(data.sites, hasLength(6));
    expect(data.sales, hasLength(9));
    expect(data.actions, hasLength(4));

    // Rendez-vous dans l'ordre de l'ERP : le plus ancien d'abord.
    expect(overview.upcoming.map((s) => s.customerName), [
      'Mme Inès Roussel',
      'Mme Camille Lefèvre',
      'M. Hugo Marchand',
      'M. Théo Garnier',
    ]);
    expect(
      overview.upcoming[1].appointmentDate,
      DateTime(2026, 11, 12, 18, 30).millisecondsSinceEpoch,
    );
    expect(overview.requests.single.customerName, 'Mme Léa Fontaine');
    expect(overview.pipeline[BadgeSaleStatus.rdv], 4);
    expect(overview.badgesCopied, 7);
    expect(overview.sites['siteTilleuls']!.status, SiteStatus.client);
    expect(overview.sites['siteJeanne']!.status, SiteStatus.prospecte);
    expect(
      overview.sites['siteParking']!.status,
      SiteStatus.prospecte,
      reason: 'une demande en cours',
    );
    expect(overview.sites['siteParc']!.status, SiteStatus.bloque);
    expect(overview.sites['siteBoulangerie']!.broughtContacts, 1);

    // L'autre établissement n'a pas de données : la vue se vide sans erreur.
    app.auth.selectIssuer('demoIssuer0000000002');
    await app.badges.refresh();
    expect(app.badges.data!.sites, isEmpty);
    expect(app.badges.overview!.upcoming, isEmpty);
  });

  group('erreurs', () {
    test('les messages de Firebase Auth sont classés', () async {
      final backend = DemoBackend();
      final api = FirebaseAuthApi(backend.config, ErpHttp(backend.client));
      await expectLater(
        api.signInWithPassword(DemoBackend.email, 'faux'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthFailure.invalidCredentials,
          ),
        ),
      );
      await expectLater(
        api.refresh('jeton-inconnu', email: DemoBackend.email),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthFailure.sessionExpired,
          ),
        ),
      );
      backend.offline = true;
      await expectLater(
        api.signInWithPassword(DemoBackend.email, DemoBackend.password),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthFailure.network,
          ),
        ),
      );
    });

    test(
      'la réponse de checkTrustedDevice est interprétée comme dans l\'ERP',
      () {
        expect(
          interpretTrustCheck({'trusted': true, 'expiresAt': 1}).trusted,
          isTrue,
        );
        final expired = interpretTrustCheck({
          'trusted': false,
          'reason': 'expired',
        });
        expect(
          (expired.trusted, expired.forget, expired.notice),
          (false, true, TrustNotice.expired),
        );
        final unknown = interpretTrustCheck({
          'trusted': false,
          'reason': 'unknown',
        });
        expect((unknown.forget, unknown.notice), (true, TrustNotice.revoked));
        final invalid = interpretTrustCheck({
          'trusted': false,
          'reason': 'invalid',
        });
        expect((invalid.forget, invalid.notice), (true, null));
        // Réponse inattendue : rien n'est effacé.
        for (final odd in <Object?>[
          null,
          'oui',
          {'trusted': 'true'},
          <String, Object?>{},
        ]) {
          final verdict = interpretTrustCheck(odd);
          expect(
            (verdict.trusted, verdict.forget),
            (false, false),
            reason: '$odd',
          );
        }
      },
    );

    test('un jeton d\'appareil mal formé est refusé', () {
      const id = 'abcdefghij0123456789';
      final token = 'A' * 43;
      expect(
        TrustedDevice.parse({'deviceId': id, 'token': token, 'expiresAt': 5})
            ?.expiresAt,
        5,
      );
      expect(
        TrustedDevice.parse({
          'deviceId': 'court',
          'token': token,
          'expiresAt': 5,
        }),
        isNull,
      );
      expect(
        TrustedDevice.parse({'deviceId': id, 'token': 'court', 'expiresAt': 5}),
        isNull,
      );
      expect(
        TrustedDevice.parse({
          'deviceId': id,
          'token': token,
          'expiresAt': 'demain',
        }),
        isNull,
      );
      expect(TrustedDevice.parse('texte'), isNull);
    });
  });

  group('stockage de la session', () {
    test(
      'chiffrement Windows : aller-retour, et rien de lisible sur le disque',
      () {
        final protector = DpapiProtector();
        final secret = Uint8List.fromList(
          utf8.encode('jeton-de-renouvellement-très-secret'),
        );
        final stored = protector.protect(secret);
        expect(stored, isNot(secret));
        expect(
          latin1.decode(stored),
          isNot(contains('jeton-de-renouvellement')),
        );
        expect(protector.unprotect(stored), secret);
        // Une valeur altérée ou étrangère ne se relit pas.
        expect(protector.unprotect(Uint8List.fromList([1, 2, 3, 4])), isNull);
      },
      skip: Platform.isWindows ? false : 'Chiffrement propre à Windows',
    );

    test('les secrets rangés dans les préférences se relisent', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PrefsSecretStore(prefs);
      await store.write('session', '{"refreshToken":"abc"}');
      expect(await store.read('session'), '{"refreshToken":"abc"}');
      final raw = prefs.getString('erp_secret_session')!;
      if (Platform.isWindows) {
        expect(raw, startsWith('dpapi:'));
        expect(raw, isNot(contains('abc')));
        expect(
          utf8.decode(base64Decode(raw.substring(6)), allowMalformed: true),
          isNot(contains('refreshToken')),
        );
      }
      // Valeur écrite avec une autre protection : ignorée plutôt que mal relue.
      await prefs.setString('erp_secret_autre', 'inconnu:AAAA');
      expect(await store.read('autre'), isNull);
      await store.delete('session');
      expect(await store.read('session'), isNull);
    });
  });
}
