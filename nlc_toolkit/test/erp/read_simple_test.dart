// Mode simple de l'écran Lecture : un seul bouton « Lire », sans choix de fréquence ni de
// configuration. Le mode avancé garde l'interface complète.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/demo/demo_backend.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/secret_store.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/page/read_card.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';

void main() {
  late SharedPreferencesProvider prefs;
  late NlcAppState appState;
  late ErpServices erp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'locale': 'fr',
      'mct_bundled_dictionaries_seeded_v1': true,
    });
    prefs = SharedPreferencesProvider();
    await prefs.load();
    appState = NlcAppState(prefs);
    final backend = DemoBackend();
    erp = ErpServices.create(
      config: backend.config,
      client: backend.client,
      secrets: MemorySecretStore(),
      localState: MemoryKeyValueStore(),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NlcAppState>.value(value: appState),
          ChangeNotifierProvider<SharedPreferencesProvider>.value(value: prefs),
          Provider<ErpServices>.value(value: erp),
        ],
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ReadCardPage(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('mode simple : un seul bouton Lire, sans config', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(FilledButton, 'Lire'), findsOneWidget);
    // Pas de choix de fréquence en mode simple (il n'existe qu'en avancé).
    expect(find.text('LF'), findsNothing);
    expect(find.text('HF'), findsNothing);
  });

  testWidgets('mode avancé : le choix de fréquence réapparaît', (tester) async {
    prefs.setAdvancedMode(true);
    await pump(tester);
    expect(find.text('LF'), findsOneWidget);
    expect(find.text('HF'), findsOneWidget);
  });
}
