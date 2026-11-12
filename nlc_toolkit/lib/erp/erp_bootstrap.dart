import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_controller.dart';
import 'demo/demo_backend.dart';
import 'erp_config.dart';
import 'erp_http.dart';
import 'erp_services.dart';
import 'secret_store.dart';

/// Mode démonstration : l'application tourne contre un faux ERP en mémoire, sans réseau et sans
/// toucher aux données réelles. Il sert à vérifier l'interface pendant le développement.
///
/// Il se demande par des variables d'environnement et n'existe pas dans une version publiée :
///   NLC_DEMO=1            active le mode
///   NLC_DEMO_STAGE        `login`, `code` ou `ready` (par défaut) : écran où s'arrêter
///   NLC_DEMO_PAGE         page ouverte : `dashboard`, `read`, `device`, `tools`, `settings`…
///   NLC_DEMO_MODE         `simple` ou `advanced`
///   NLC_DEMO_DEVICE=1     lecteur simulé
///   NLC_DEMO_ZOOM         échelle d'affichage (0.5 montre deux fois plus de surface)
class DemoOptions {
  const DemoOptions({
    this.stage = 'ready',
    this.pageName,
    this.advanced,
    this.emulatedDevice = false,
    this.zoom,
  });

  final String stage;
  final String? pageName;
  final bool? advanced;
  final bool emulatedDevice;
  final double? zoom;

  static DemoOptions? fromEnvironment() {
    if (kReleaseMode) return null;
    final env = Platform.environment;
    if (env['NLC_DEMO'] != '1') return null;
    return DemoOptions(
      stage: env['NLC_DEMO_STAGE'] ?? 'ready',
      pageName: env['NLC_DEMO_PAGE'],
      advanced: switch (env['NLC_DEMO_MODE']) {
        'advanced' => true,
        'simple' => false,
        _ => null,
      },
      emulatedDevice: env['NLC_DEMO_DEVICE'] == '1',
      zoom: double.tryParse(env['NLC_DEMO_ZOOM'] ?? ''),
    );
  }
}

/// Assemble la liaison avec l'ERP : le projet configuré à la compilation, ou le faux ERP en
/// mode démonstration.
Future<ErpServices> createErpServices({DemoOptions? demo}) async {
  if (!kReleaseMode && demo != null) {
    final backend = DemoBackend();
    return ErpServices.create(
      config: backend.config,
      client: backend.client,
      secrets: MemorySecretStore(),
      localState: MemoryKeyValueStore(),
    );
  }

  final prefs = await SharedPreferences.getInstance();
  var version = '';
  try {
    version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // Sans numéro de version, l'appareil est simplement désigné par son système.
  }
  return ErpServices.create(
    config: ErpConfig.fromEnvironment(),
    client: http.Client(),
    secrets: PrefsSecretStore(prefs),
    localState: PrefsKeyValueStore(prefs),
    userAgent:
        'NLC Toolkit${version.isEmpty ? '' : '/$version'} (${erpPlatformLabel()})',
  );
}

/// Reprend la session enregistrée. En mode démonstration, avance jusqu'à l'écran demandé.
Future<void> startErpSession(ErpServices erp, {DemoOptions? demo}) async {
  await erp.auth.start();
  if (kReleaseMode || demo == null || demo.stage == 'login') return;
  await erp.auth.signIn(DemoBackend.email, DemoBackend.password);
  if (demo.stage == 'code') return;
  await erp.auth.verifyCode(DemoBackend.validCode, rememberDevice: true);
  erp.auth.selectIssuer(DemoBackend.mainIssuerId);
}
