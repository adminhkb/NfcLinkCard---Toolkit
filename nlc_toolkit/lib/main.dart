import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:nlc_toolkit/bridge/chameleon.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/connector/serial_android.dart';
import 'package:nlc_toolkit/connector/serial_ble.dart';
import 'package:nlc_toolkit/connector/serial_emulator.dart';
import 'package:nlc_toolkit/connector/serial_macos.dart';
import 'package:nlc_toolkit/connector/serial_native.dart';
import 'package:nlc_toolkit/connector/serial_windows_ble.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/badge_controller.dart';
import 'package:nlc_toolkit/erp/erp_bootstrap.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/auth/auth_pages.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/shell/app_shell.dart';
import 'package:nlc_toolkit/gui/shell/navigation.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:provider/provider.dart';

export 'package:nlc_toolkit/erp/erp_bootstrap.dart' show DemoOptions;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  final demo = DemoOptions.fromEnvironment();
  final erp = await createErpServices(demo: demo);
  runApp(NlcToolkitApp(sharedPreferencesProvider, erp, demo: demo));
  unawaited(startErpSession(erp, demo: demo));
}

/// Racine de l'application : état partagé, thème, puis accès (connexion) et coque.
class NlcToolkitApp extends StatelessWidget {
  const NlcToolkitApp(
    this._sharedPreferencesProvider,
    this._erp, {
    super.key,
    this.demo,
  });

  final SharedPreferencesProvider _sharedPreferencesProvider;
  final ErpServices _erp;
  final DemoOptions? demo;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider(
          create: (context) =>
              NlcAppState(_sharedPreferencesProvider, demo: demo),
        ),
        ChangeNotifierProvider<AuthController>.value(value: _erp.auth),
        ChangeNotifierProvider<BadgeController>.value(value: _erp.badges),
        Provider<ErpServices>.value(value: _erp),
        ChangeNotifierProvider(
          create: (context) => NlcNavigation(
            NlcDestination.byName(demo?.pageName) ?? NlcDestination.dashboard,
          ),
        ),
      ],
      child: Builder(
        builder: (context) {
          // La langue suit les réglages : l'application se reconstruit quand ils changent.
          final preferences = context.watch<SharedPreferencesProvider>();
          return MaterialApp(
            title: 'NLC Toolkit',
            debugShowCheckedModeBanner: false,
            locale: preferences.getLocale(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: NlcTheme.dark,
            darkTheme: NlcTheme.dark,
            themeMode: ThemeMode.dark,
            builder: demo?.zoom == null
                ? null
                : (context, child) =>
                      _DemoZoom(zoom: demo!.zoom!, child: child!),
            home: AuthGate(
              configured: _erp.config.isConfigured,
              builder: (context) => const AppShell(),
            ),
          );
        },
      ),
    );
  }
}

/// Mode démonstration : affiche l'application à une autre échelle pour voir une page entière.
class _DemoZoom extends StatelessWidget {
  const _DemoZoom({required this.zoom, required this.child});

  final double zoom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest / zoom;
        return FittedBox(
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: size),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

enum DeviceIoCompatibility {
  supported,
  ultraRequired,
  legacyProtocol,
  missingCommands,
  checkFailed,
}

class NlcAppState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;

  /// Réglages imposés par le mode démonstration (jamais en version publiée).
  final DemoOptions? demo;

  NlcAppState(this.sharedPreferencesProvider, {this.demo});

  Logger? log; // Logger

  // Android uses AndroidSerial, iOS can only use BLESerial
  // The rest (desktops?) can use NativeSerial
  AbstractSerial? connector;
  ChameleonCommunicator? communicator;
  ChameleonCommunicator? _checkedCommunicator;
  Future<DeviceIoCompatibility>? _deviceIoCompatibility;

  bool devMode = false;
  double? progress; // DFU

  // Flashing easter egg
  bool easterEgg = false;
  dynamic _suppressedAutoReconnectPort;

  /// Mode d'affichage avancé : tous les outils dans le menu.
  bool get advancedMode =>
      demo?.advanced ?? sharedPreferencesProvider.getAdvancedMode();

  /// Crée le journal et le connecteur de l'appareil s'ils n'existent pas encore.
  /// Appelé à chaque affichage : les réglages peuvent demander un nouveau connecteur.
  void ensureServices() {
    log ??= _createLogger();
    connector ??= _createConnector();
    connector!.connectionStateCallback = onConnectorStateChanged;
    devMode = sharedPreferencesProvider.isDebugMode();
  }

  /// Mode démonstration : branche le lecteur simulé sans passer par la page de connexion.
  Future<void> connectDemoDevice() async {
    if (demo?.emulatedDevice != true) return;
    ensureServices();
    final port = connector!;
    if (port.connected) return;
    final devices = await port.availableChameleons(false);
    if (devices.isEmpty ||
        !await port.connectSpecificDevice(devices.first.port)) {
      return;
    }
    communicator = ChameleonCommunicator(log!, port: port);
    notifyListeners();
  }

  AbstractSerial _createConnector() {
    if (demo?.emulatedDevice == true ||
        sharedPreferencesProvider.isEmulatedChameleon()) {
      return EmulatorSerial(log: log!);
    }
    if (Platform.isMacOS) return MacOSSerial(log: log!);
    if (Platform.isAndroid) return AndroidSerial(log: log!);
    // iOS ne donne accès qu'au Bluetooth.
    if (Platform.isIOS) return BLESerial(log: log!);
    // Windows : Bluetooth en option (réglage), sinon USB.
    if (Platform.isWindows && sharedPreferencesProvider.getBluetoothDesktop()) {
      return WindowsBleSerial(log: log!);
    }
    return NativeSerial(log: log!);
  }

  Logger _createLogger() {
    if (sharedPreferencesProvider.isDebugLogging() &&
        sharedPreferencesProvider.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(sharedPreferencesProvider),
        printer: PrettyPrinter(noBoxingByDefault: true),
        filter: ChameleonLogFilter(),
      );
    }
    return Logger();
  }

  void changesMade() {
    notifyListeners();
  }

  void onConnectorStateChanged() {
    if (connector == null || !connector!.connected) {
      communicator = null;
      progress = null;
      _checkedCommunicator = null;
      _deviceIoCompatibility = null;
    }
    notifyListeners();
  }

  Future<DeviceIoCompatibility> checkDeviceIoCompatibility() {
    final activeCommunicator = communicator;
    if (connector?.connected != true ||
        connector?.device != ChameleonDevice.ultra) {
      return Future.value(DeviceIoCompatibility.ultraRequired);
    }
    if (activeCommunicator == null) {
      return Future.value(DeviceIoCompatibility.checkFailed);
    }
    if (!identical(_checkedCommunicator, activeCommunicator) ||
        _deviceIoCompatibility == null) {
      _checkedCommunicator = activeCommunicator;
      _deviceIoCompatibility = _loadDeviceIoCompatibility(activeCommunicator);
    }
    return _deviceIoCompatibility!;
  }

  Future<DeviceIoCompatibility> _loadDeviceIoCompatibility(
    ChameleonCommunicator activeCommunicator,
  ) async {
    try {
      final firmware = await activeCommunicator.getFirmwareVersion();
      if (firmware.legacyProtocol) {
        return DeviceIoCompatibility.legacyProtocol;
      }
      final capabilities = await activeCommunicator.getDeviceCapabilities();
      final requiredCommands = [
        ChameleonCommand.getDeviceMode.value,
        ChameleonCommand.changeDeviceMode.value,
        ChameleonCommand.scan14ATag.value,
        ChameleonCommand.hf14ARawCommand.value,
        ChameleonCommand.mf1SupportDetect.value,
        ChameleonCommand.mf1CheckKey.value,
        ChameleonCommand.mf1ReadBlock.value,
        ChameleonCommand.mf1WriteBlock.value,
      ];
      if (!requiredCommands.every(capabilities.contains)) {
        return DeviceIoCompatibility.missingCommands;
      }
      return DeviceIoCompatibility.supported;
    } catch (error) {
      log?.e(error);
      return DeviceIoCompatibility.checkFailed;
    }
  }

  void retryDeviceIoCompatibility() {
    _deviceIoCompatibility = null;
    notifyListeners();
  }

  bool isAutoReconnectSuppressed(dynamic devicePort) {
    return _suppressedAutoReconnectPort == devicePort;
  }

  void clearAutoReconnectSuppression([dynamic devicePort]) {
    if (devicePort == null || _suppressedAutoReconnectPort == devicePort) {
      _suppressedAutoReconnectPort = null;
    }
  }

  void syncAutoReconnectSuppression(Iterable<dynamic> visiblePorts) {
    if (_suppressedAutoReconnectPort == null) {
      return;
    }

    for (final port in visiblePorts) {
      if (port == _suppressedAutoReconnectPort) {
        return;
      }
    }

    _suppressedAutoReconnectPort = null;
  }

  Future<void> disconnect({bool manual = false}) async {
    final suppressedPort = manual ? connector?.activeDevicePort : null;
    await connector?.performDisconnect();
    if (manual && suppressedPort != null) {
      _suppressedAutoReconnectPort = suppressedPort;
    }
    communicator = null;
    progress = null;
    _checkedCommunicator = null;
    _deviceIoCompatibility = null;
    notifyListeners();
  }

  void setProgressBar(dynamic value) {
    progress = value;
    notifyListeners();
  }
}
