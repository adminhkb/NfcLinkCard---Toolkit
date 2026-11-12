// Parcours de connexion à l'ERP, joués contre le faux serveur en mémoire (aucun accès réseau).
import 'package:flutter_test/flutter_test.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/demo/demo_backend.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/secret_store.dart';
import 'package:nlc_toolkit/erp/trusted_device.dart';

class _Bench {
  _Bench({DateTime? start}) : clock = start ?? DateTime(2026, 11, 12, 14, 30) {
    backend = DemoBackend(now: () => clock);
  }

  DateTime clock;
  late final DemoBackend backend;
  final secrets = MemorySecretStore();
  final local = MemoryKeyValueStore();

  /// Une nouvelle ouverture de l'application : mêmes secrets enregistrés, état en mémoire perdu.
  ErpServices launch() => ErpServices.create(
    config: backend.config,
    client: backend.client,
    secrets: secrets,
    localState: local,
    now: () => clock,
  );

  Future<ErpServices> signedIn({bool remember = false}) async {
    final app = launch();
    await app.auth.start();
    await app.auth.signIn(DemoBackend.email, DemoBackend.password);
    await app.auth.verifyCode(DemoBackend.validCode, rememberDevice: remember);
    expect(app.auth.stage, AuthStage.ready);
    return app;
  }
}

void main() {
  test(
    'sans session enregistrée, l\'application ouvre l\'écran de connexion',
    () async {
      final app = _Bench().launch();
      expect(app.auth.stage, AuthStage.starting);
      await app.auth.start();
      expect(app.auth.stage, AuthStage.signedOut);
      expect(app.auth.notice, isNull);
    },
  );

  test(
    'un mauvais mot de passe reste sur l\'écran de connexion avec un message',
    () async {
      final bench = _Bench();
      final app = bench.launch();
      await app.auth.start();
      await app.auth.signIn(DemoBackend.email, 'mauvais');
      expect(app.auth.stage, AuthStage.signedOut);
      expect(app.auth.notice, AuthNotice.invalidCredentials);
      expect(app.auth.busy, isFalse);
      expect(
        bench.secrets.values,
        isEmpty,
        reason: 'rien ne doit être enregistré',
      );
    },
  );

  test('connexion puis code : l\'application s\'ouvre et charge les établissements', () async {
    final bench = _Bench();
    final app = bench.launch();
    await app.auth.start();
    await app.auth.signIn('  ${DemoBackend.email} ', DemoBackend.password);

    expect(app.auth.stage, AuthStage.secondFactor);
    expect(app.auth.user?.email, DemoBackend.email);
    expect(
      bench.backend.codesSent,
      0,
      reason: "c'est l'écran du code qui déclenche l'envoi",
    );

    await app.auth.sendCode();
    expect(bench.backend.codesSent, 1);
    expect(app.auth.codeResendWait, AuthController.codeResendDelay);

    expect(await app.auth.verifyCode('000000'), isFalse);
    expect(app.auth.stage, AuthStage.secondFactor);
    expect(app.auth.notice, AuthNotice.invalidCode);
    expect(app.auth.noticeDetail, 'Le code saisi est incorrect.');

    expect(await app.auth.verifyCode(DemoBackend.validCode), isTrue);
    expect(app.auth.stage, AuthStage.ready);
    expect(app.auth.offline, isFalse);
    expect(app.auth.issuers.map((i) => i.name), [
      'Atelier Badges (démonstration)',
      'Société Exemple (démonstration)',
    ]);
    expect(app.auth.currentIssuer?.id, isNotNull);
    expect(app.auth.hasTrustedDevice, isFalse);
  });

  test(
    'sans appareil mémorisé, le code est redemandé à chaque ouverture',
    () async {
      final bench = _Bench();
      await bench.signedIn();

      final reopened = bench.launch();
      await reopened.auth.start();
      expect(reopened.auth.stage, AuthStage.secondFactor);
      expect(reopened.auth.user?.uid, DemoBackend.uid);
      expect(reopened.auth.trustNotice, isNull);
    },
  );

  test('appareil mémorisé : la réouverture ne demande plus le code', () async {
    final bench = _Bench();
    final first = await bench.signedIn(remember: true);
    expect(first.auth.hasTrustedDevice, isTrue);
    expect(bench.backend.trustedDevices, hasLength(1));

    final reopened = bench.launch();
    await reopened.auth.start();
    expect(reopened.auth.stage, AuthStage.ready);
    expect(reopened.auth.hasTrustedDevice, isTrue);
    expect(bench.backend.calls, contains('POST checkTrustedDevice'));
  });

  test('appareil révoqué depuis l\'ERP : le code est redemandé et le jeton local oublié', () async {
    final bench = _Bench();
    await bench.signedIn(remember: true);
    bench.backend.trustedDevices.clear();

    final reopened = bench.launch();
    await reopened.auth.start();
    expect(reopened.auth.stage, AuthStage.secondFactor);
    expect(reopened.auth.trustNotice, TrustNotice.revoked);
    expect(
      await TrustedDeviceStore(bench.secrets).load(DemoBackend.uid),
      isNull,
    );
  });

  test('mémorisation expirée après 30 jours', () async {
    final bench = _Bench();
    await bench.signedIn(remember: true);
    bench.clock = bench.clock.add(const Duration(days: 31));

    final reopened = bench.launch();
    await reopened.auth.start();
    expect(reopened.auth.stage, AuthStage.secondFactor);
    expect(reopened.auth.trustNotice, TrustNotice.expired);
  });

  test('un nouveau code mémorisé remplace l\'ancien appareil', () async {
    final bench = _Bench();
    final app = await bench.signedIn(remember: true);
    final firstId = bench.backend.trustedDevices.keys.single;

    await app.auth.signOut();
    await app.auth.signIn(DemoBackend.email, DemoBackend.password);
    expect(
      app.auth.stage,
      AuthStage.ready,
      reason: "l'appareil reste mémorisé après une déconnexion",
    );

    // La vérification de l'appareil tombe en panne : pas de réponse définitive, le jeton est gardé
    // et le code est demandé. Le nouveau jeton remplace alors l'ancien côté serveur.
    bench.backend.brokenFunctions.add('checkTrustedDevice');
    final reopened = bench.launch();
    await reopened.auth.start();
    expect(reopened.auth.stage, AuthStage.secondFactor);
    expect(reopened.auth.trustNotice, isNull);
    expect(
      await TrustedDeviceStore(bench.secrets).load(DemoBackend.uid),
      isNotNull,
    );

    bench.backend.brokenFunctions.clear();
    await reopened.auth.verifyCode(DemoBackend.validCode, rememberDevice: true);
    expect(reopened.auth.stage, AuthStage.ready);
    expect(bench.backend.trustedDevices.keys.single, isNot(firstId));
  });

  test('compte sans accès à l\'ERP : déconnexion immédiate avec le message de l\'ERP', () async {
    final bench = _Bench();
    bench.backend.documents.removeWhere((path, _) => path.startsWith('users/'));
    final app = bench.launch();
    await app.auth.start();
    await app.auth.signIn(DemoBackend.email, DemoBackend.password);
    expect(app.auth.stage, AuthStage.signedOut);
    expect(app.auth.notice, AuthNotice.notAuthorized);
    expect(bench.secrets.values.keys, isNot(contains('session')));
  });

  test('administrateur autorisé d\'un seul établissement : il ne voit que le sien', () async {
    final bench = _Bench();
    bench.backend.documents['users/${DemoBackend.uid}'] = {'isAdmin': false};
    bench
        .backend
        .documents['issuers/${DemoBackend.mainIssuerId}']!['allowedAdmins'] = [
      DemoBackend.uid,
    ];
    final app = bench.launch();
    await app.auth.start();
    await app.auth.signIn(DemoBackend.email, DemoBackend.password);
    expect(app.auth.stage, AuthStage.secondFactor);
    await app.auth.verifyCode(DemoBackend.validCode);
    expect(app.auth.issuers.map((i) => i.id), [DemoBackend.mainIssuerId]);
    expect(app.auth.isAdmin, isFalse);
  });

  test(
    'les secrets de la fiche établissement ne sont jamais demandés',
    () async {
      final bench = _Bench();
      final app = await bench.signedIn();
      // Le faux serveur applique le masque de champs comme Firestore : la fiche contient un bloc
      // smtpConfig, qui ne doit apparaître nulle part côté application.
      expect(app.auth.issuers, isNotEmpty);
      expect(bench.backend.unmaskedIssuerReads, 0);
      expect(bench.local.values.values.join(), isNot(contains('smtp')));
    },
  );

  test('hors connexion avec appareil mémorisé : ouverture sans les données de l\'ERP', () async {
    final bench = _Bench();
    await bench.signedIn(remember: true);
    bench.backend.offline = true;

    final reopened = bench.launch();
    await reopened.auth.start();
    expect(reopened.auth.stage, AuthStage.ready);
    expect(reopened.auth.offline, isTrue);
    expect(
      reopened.auth.issuers,
      hasLength(2),
      reason: 'liste gardée de la dernière connexion',
    );
    expect(reopened.badges.available, isFalse);

    // Le réseau revient : la vérification se fait sans quitter l'application.
    bench.backend.offline = false;
    await reopened.auth.retry();
    expect(reopened.auth.stage, AuthStage.ready);
    expect(reopened.auth.offline, isFalse);
    expect(reopened.badges.available, isTrue);
  });

  test('hors connexion, un appareil révoqué entre-temps redemande le code au retour du réseau', () async {
    final bench = _Bench();
    await bench.signedIn(remember: true);
    bench.backend.offline = true;
    final reopened = bench.launch();
    await reopened.auth.start();
    expect(reopened.auth.offline, isTrue);

    bench.backend
      ..offline = false
      ..trustedDevices.clear();
    await reopened.auth.retry();
    expect(reopened.auth.stage, AuthStage.secondFactor);
    expect(reopened.auth.trustNotice, TrustNotice.revoked);
  });

  test(
    'hors connexion sans appareil mémorisé : l\'application reste fermée',
    () async {
      final bench = _Bench();
      await bench.signedIn();
      bench.backend.offline = true;

      final reopened = bench.launch();
      await reopened.auth.start();
      expect(reopened.auth.stage, AuthStage.unreachable);
      expect(reopened.auth.notice, AuthNotice.network);

      bench.backend.offline = false;
      await reopened.auth.retry();
      expect(reopened.auth.stage, AuthStage.secondFactor);
    },
  );

  test('hors connexion, une mémorisation expirée localement n\'ouvre pas l\'application', () async {
    final bench = _Bench();
    await bench.signedIn(remember: true);
    bench.clock = bench.clock.add(const Duration(days: 31));
    bench.backend.offline = true;

    final reopened = bench.launch();
    await reopened.auth.start();
    expect(reopened.auth.stage, AuthStage.unreachable);
  });

  test('première connexion impossible sans réseau', () async {
    final bench = _Bench();
    bench.backend.offline = true;
    final app = bench.launch();
    await app.auth.start();
    await app.auth.signIn(DemoBackend.email, DemoBackend.password);
    expect(app.auth.stage, AuthStage.signedOut);
    expect(app.auth.notice, AuthNotice.network);
  });

  test('compte désactivé : la session enregistrée est effacée', () async {
    final bench = _Bench();
    await bench.signedIn(remember: true);
    bench.backend.accountDisabled = true;

    final reopened = bench.launch();
    await reopened.auth.start();
    expect(reopened.auth.stage, AuthStage.signedOut);
    expect(reopened.auth.notice, AuthNotice.userDisabled);
    expect(bench.secrets.values.keys, isNot(contains('session')));
  });

  test('le jeton d\'identité est renouvelé avant son expiration', () async {
    final bench = _Bench();
    final app = await bench.signedIn();
    final first = await app.auth.idToken();
    expect(
      await app.auth.idToken(),
      first,
      reason: 'encore valable : pas de nouvel appel',
    );

    bench.clock = bench.clock.add(const Duration(minutes: 56));
    final renewed = await app.auth.idToken();
    expect(renewed, isNot(first));
    expect(bench.backend.calls.where((c) => c == 'POST token'), hasLength(1));
  });

  test('déconnexion : session effacée, appareil gardé', () async {
    final bench = _Bench();
    final app = await bench.signedIn(remember: true);
    await app.auth.signOut();
    expect(app.auth.stage, AuthStage.signedOut);
    expect(app.auth.user, isNull);
    expect(app.auth.issuers, isEmpty);
    expect(bench.secrets.values.keys, ['trusted_device_${DemoBackend.uid}']);
  });

  test('« oublier cet appareil » le révoque aussi côté serveur', () async {
    final bench = _Bench();
    final app = await bench.signedIn(remember: true);
    await app.auth.forgetThisDevice();
    expect(app.auth.hasTrustedDevice, isFalse);
    expect(bench.backend.trustedDevices, isEmpty);
    expect(bench.secrets.values.keys, ['session']);
  });

  test(
    'le changement d\'établissement est retenu pour la prochaine ouverture',
    () async {
      final bench = _Bench();
      final app = await bench.signedIn(remember: true);
      final other = app.auth.issuers.firstWhere(
        (i) => i.id != app.auth.currentIssuer!.id,
      );
      app.auth.selectIssuer(other.id);
      expect(app.auth.currentIssuer?.id, other.id);

      final reopened = bench.launch();
      await reopened.auth.start();
      expect(reopened.auth.currentIssuer?.id, other.id);
    },
  );
}
