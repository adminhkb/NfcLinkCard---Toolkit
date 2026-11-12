// Interface des dumps : la section « Badges enregistrés » d'un immeuble et le flux d'enregistrement
// depuis une carte, joués contre le faux ERP en mémoire.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/demo/demo_backend.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/secret_store.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/page/badge_dumps_ui.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';

void main() {
  late DemoBackend backend;
  late ErpServices erp;

  setUp(() async {
    backend = DemoBackend();
    erp = ErpServices.create(
      config: backend.config,
      client: backend.client,
      secrets: MemorySecretStore(),
      localState: MemoryKeyValueStore(),
    );
    await erp.auth.start();
    await erp.auth.signIn(DemoBackend.email, DemoBackend.password);
    await erp.auth.verifyCode(DemoBackend.validCode, rememberDevice: false);
    erp.auth.selectIssuer(DemoBackend.mainIssuerId);
    await erp.badges.refresh();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      Provider<ErpServices>.value(
        value: erp,
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('la section d\'un immeuble montre ses badges enregistrés', (
    tester,
  ) async {
    await pump(tester, const SiteDumpsSection(siteId: 'siteTilleuls'));
    // Le titre de section est affiché en majuscules par le thème.
    expect(find.text('BADGES ENREGISTRÉS'), findsOneWidget);
    expect(find.text('Les Tilleuls — hall A'), findsOneWidget);

    // Un immeuble sans dump l'indique.
    await pump(tester, const SiteDumpsSection(siteId: 'siteJeanne'));
    expect(find.textContaining('Aucun badge enregistré'), findsOneWidget);
  });

  testWidgets('enregistrer une carte sur un immeuble choisi', (tester) async {
    final card = CardSave(
      uid: '04AABBCC',
      name: 'Badge test',
      tag: TagType.mifare1K,
    );

    await pump(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => saveCardToSite(context, card),
          child: const Text('Enregistrer'),
        ),
      ),
    );

    // Avant : un seul dump d'exemple sur l'établissement.
    final before = backend.documents.keys
        .where((k) => k.contains('/badge_dumps/'))
        .length;

    await tester.tap(find.text('Enregistrer'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    // Le choix de l'immeuble s'ouvre.
    expect(find.text('Enregistrer sur un immeuble'), findsOneWidget);
    expect(find.text('Résidence Les Tilleuls'), findsOneWidget);

    await tester.tap(find.text("Immeuble Jeanne d'Arc"));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final after = backend.documents.entries
        .where((e) => e.key.contains('/badge_dumps/'))
        .toList();
    expect(after.length, before + 1);
    // Le dump est bien rattaché à l'immeuble choisi, avec un fichier dans Storage.
    final saved = after.firstWhere((e) => e.value['siteId'] == 'siteJeanne');
    expect(saved.value['name'], 'Badge test');
    expect(
      backend.storageObjects.containsKey(saved.value['storagePath']),
      isTrue,
    );
  });
}
