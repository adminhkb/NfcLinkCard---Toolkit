// Parcours à l'écran : connexion, code de sécurité, ouverture de l'application, déconnexion.
// L'application entière tourne contre le faux ERP en mémoire, avec un lecteur simulé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/demo/demo_backend.dart';
import 'package:nlc_toolkit/erp/erp_config.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/secret_store.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/auth/auth_pages.dart';
import 'package:nlc_toolkit/gui/page/dashboard.dart';
import 'package:nlc_toolkit/gui/page/dashboard_map.dart';
import 'package:nlc_toolkit/gui/page/device_gate.dart';
import 'package:nlc_toolkit/gui/shell/app_shell.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DemoBackend backend;
  late ErpServices erp;
  late SharedPreferencesProvider preferences;

  setUp(() async {
    SitesMap.tilesEnabled = false;
    SharedPreferences.setMockInitialValues({
      'locale': 'fr',
      'mct_bundled_dictionaries_seeded_v1': true,
    });
    preferences = SharedPreferencesProvider();
    await preferences.load();
    backend = DemoBackend();
    erp = ErpServices.create(
      config: backend.config,
      client: backend.client,
      secrets: MemorySecretStore(),
      localState: MemoryKeyValueStore(),
    );
  });

  tearDown(() => SitesMap.tilesEnabled = true);

  /// Laisse passer le temps des appels et des transitions. Les animations qui tournent en boucle
  /// (voyant « à jour », attente) empêchent d'attendre un écran parfaitement immobile.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openApp(
    WidgetTester tester, {
    Size size = const Size(1280, 900),
    bool emulatedDevice = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NlcToolkitApp(
        preferences,
        erp,
        demo: DemoOptions(stage: 'login', emulatedDevice: emulatedDevice),
      ),
    );
    erp.auth.start();
    await settle(tester);
  }

  Future<void> signIn(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextField).at(0), DemoBackend.email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.tap(find.text('Se connecter'));
    await settle(tester);
  }

  testWidgets('connexion, code de sécurité puis tableau de bord', (
    tester,
  ) async {
    await openApp(tester, emulatedDevice: true);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Connectez-vous avec votre compte ERP'), findsOneWidget);

    await signIn(tester, 'mauvais-mot-de-passe');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Identifiants de connexion incorrects.'), findsOneWidget);

    await signIn(tester, DemoBackend.password);
    expect(find.byType(TwoFactorPage), findsOneWidget);
    expect(find.text('Vérification de sécurité'), findsOneWidget);
    expect(
      find.text('d**o@n**.test'),
      findsOneWidget,
      reason: 'adresse masquée comme dans l\'ERP',
    );
    expect(
      backend.codesSent,
      1,
      reason: 'le code part dès l\'affichage de l\'écran',
    );

    // Le bouton reste inactif tant que le code n'a pas six chiffres.
    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    await tester.tap(find.text('Valider et se connecter'));
    await settle(tester);
    expect(find.byType(TwoFactorPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    await tester.tap(find.text('Valider et se connecter'));
    await settle(tester);
    expect(find.text('Le code saisi est incorrect.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), DemoBackend.validCode);
    await tester.pump();
    await tester.tap(find.text('Valider et se connecter'));
    await settle(tester);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(erp.auth.stage, AuthStage.ready);

    // L'établissement de démonstration et ses rendez-vous.
    erp.auth.selectIssuer(DemoBackend.mainIssuerId);
    await settle(tester);
    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.textContaining('PROCHAINS RENDEZ-VOUS · 4'), findsOneWidget);
    expect(
      find.textContaining('Mme Camille Lefèvre', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('en retard'), findsWidgets);
    expect(find.text('Résidence Les Tilleuls'), findsOneWidget);
    // Lecteur simulé branché : la carte « Appareil » le montre.
    expect(find.text('Chameleon Ultra'), findsWidgets);

    // Déconnexion : retour à l'écran de connexion, plus aucune donnée affichée.
    erp.auth.signOut();
    await settle(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Résidence Les Tilleuls'), findsNothing);
  });

  testWidgets(
    'mode simple : le menu ne montre que l\'essentiel, le mode avancé montre tout',
    (tester) async {
      await openApp(tester);
      await signIn(tester, DemoBackend.password);
      await tester.enterText(find.byType(TextField), DemoBackend.validCode);
      await tester.pump();
      await tester.tap(find.text('Valider et se connecter'));
      await settle(tester);

      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Bibliothèque'), findsNothing);
      expect(find.text('Outils'), findsNothing);

      await tester.tap(find.text('Avancé'));
      await settle(tester);
      expect(find.text('Bibliothèque'), findsOneWidget);
      expect(find.text('Outils'), findsOneWidget);
      expect(find.text('Emplacements'), findsOneWidget);
      expect(preferences.getAdvancedMode(), isTrue);

      // Sans lecteur, la lecture explique quoi faire au lieu d'ouvrir une page inutilisable.
      await tester.tap(find.text('Lire').first);
      await settle(tester);
      expect(find.byType(DeviceNeededPage), findsOneWidget);
      expect(find.text('Connecter l\'appareil'), findsOneWidget);
    },
  );

  testWidgets('écran étroit : le menu passe dans un tiroir', (tester) async {
    await openApp(tester, size: const Size(420, 860));
    await signIn(tester, DemoBackend.password);
    await tester.enterText(find.byType(TextField), DemoBackend.validCode);
    await tester.pump();
    await tester.tap(find.text('Valider et se connecter'));
    await settle(tester);

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(
      find.text('Accueil'),
      findsNothing,
      reason: 'barre latérale masquée',
    );
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('MON ENTREPRISE'), findsOneWidget);
  });

  testWidgets('sans configuration ERP, l\'application explique quoi faire', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Une compilation sans config/erp.json laisse la configuration vide.
    expect(ErpConfig.fromEnvironment().isConfigured, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AuthGate(
          configured: false,
          builder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ConfigMissingPage), findsOneWidget);
    expect(find.text('Liaison ERP non configurée'), findsOneWidget);
  });
}
