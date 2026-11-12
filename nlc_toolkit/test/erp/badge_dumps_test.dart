// Enregistrement, liste, téléchargement et suppression des dumps rattachés aux immeubles,
// joués contre le faux ERP en mémoire (Firestore et Storage simulés, aucun accès réseau).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/badge_dumps.dart';
import 'package:nlc_toolkit/erp/demo/demo_backend.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/models.dart';
import 'package:nlc_toolkit/erp/secret_store.dart';

void main() {
  late DemoBackend backend;
  late ErpServices app;

  setUp(() async {
    backend = DemoBackend();
    app = ErpServices.create(
      config: backend.config,
      client: backend.client,
      secrets: MemorySecretStore(),
      localState: MemoryKeyValueStore(),
    );
    await app.auth.start();
    await app.auth.signIn(DemoBackend.email, DemoBackend.password);
    await app.auth.verifyCode(DemoBackend.validCode, rememberDevice: false);
    app.auth.selectIssuer(DemoBackend.mainIssuerId);
  });

  NewBadgeDump dumpFor(
    String siteId, {
    String content = '{"uid":"DEADBEEF","blocks":[1,2,3]}',
    BadgeTech technology = BadgeTech.mifareCuid,
    String uid = 'DEADBEEF',
  }) => NewBadgeDump(
    siteId: siteId,
    bytes: Uint8List.fromList(utf8.encode(content)),
    name: 'Badge $siteId',
    technology: technology,
    uid: uid,
    tagType: 1001,
  );

  test(
    'enregistre un dump, le relie à l\'immeuble, le relit puis le supprime',
    () async {
      final repo = app.badgeDumps.repo()!;
      final before = await repo.listForSite('siteTilleuls');

      final payload = dumpFor('siteTilleuls');
      final saved = await repo.save(payload);
      expect(saved.siteId, 'siteTilleuls');
      expect(saved.technology, BadgeTech.mifareCuid);
      expect(saved.uid, 'DEADBEEF');
      expect(saved.byteSize, payload.bytes.length);
      expect(
        saved.storagePath,
        'issuers/${DemoBackend.mainIssuerId}/badge_dumps/${saved.id}',
      );
      // Le fichier est bien dans Storage et la référence bien dans Firestore.
      expect(backend.storageObjects.containsKey(saved.storagePath), isTrue);

      final after = await repo.listForSite('siteTilleuls');
      expect(after.length, before.length + 1);
      expect(after.map((d) => d.id), contains(saved.id));

      // Le contenu se relit à l'identique, le temps d'une copie.
      final bytes = await repo.fetch(saved);
      expect(bytes, equals(payload.bytes));

      await repo.delete(saved);
      final afterDelete = await repo.listForSite('siteTilleuls');
      expect(afterDelete.map((d) => d.id), isNot(contains(saved.id)));
      expect(
        backend.storageObjects.containsKey(saved.storagePath),
        isFalse,
        reason: 'le fichier est retiré avec la référence',
      );
    },
  );

  test(
    'un dump n\'apparaît que sur l\'immeuble auquel il est rattaché',
    () async {
      final repo = app.badgeDumps.repo()!;
      final saved = await repo.save(dumpFor('siteJeanne', uid: '01020304'));

      final jeanne = await repo.listForSite('siteJeanne');
      final tilleuls = await repo.listForSite('siteTilleuls');
      expect(jeanne.map((d) => d.id), contains(saved.id));
      expect(tilleuls.map((d) => d.id), isNot(contains(saved.id)));
      expect(tilleuls.every((d) => d.siteId == 'siteTilleuls'), isTrue);
    },
  );

  test('le dump d\'exemple est rattaché à son immeuble', () async {
    final repo = app.badgeDumps.repo()!;
    final dumps = await repo.listForSite('siteTilleuls');
    expect(dumps, isNotEmpty);
    expect(dumps.first.name, 'Les Tilleuls — hall A');
    expect(dumps.first.technology, BadgeTech.mifareUid);
  });

  test('sans établissement choisi ni en ligne, aucun dépôt', () async {
    await app.auth.signOut();
    expect(app.badgeDumps.available, isFalse);
    expect(app.badgeDumps.repo(), isNull);
  });
}
