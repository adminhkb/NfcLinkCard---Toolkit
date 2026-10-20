import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/gui/design/nlc_theme.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/gui/page/advanced.dart';
import 'package:chameleonultragui/gui/page/basic_home.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'connector/serial_native.dart';

// Page imports
import 'package:chameleonultragui/gui/page/home.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/debug.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/flashing.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/gui/page/pending_connection.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Shared Preferences Provider
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Logger
import 'package:logger/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  runApp(ChameleonGUI(sharedPreferencesProvider));
}

class ChameleonGUI extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;
  const ChameleonGUI(this._sharedPreferencesProvider, {super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider(
          create: (context) => ChameleonGUIState(_sharedPreferencesProvider),
        ),
      ],
      child: MainPage(sharedPreferencesProvider: _sharedPreferencesProvider),
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

class ChameleonGUIState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  ChameleonGUIState(this.sharedPreferencesProvider);

  SharedPreferencesProvider? _sharedPreferencesProvider;
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

  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;

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
      ChameleonCommunicator activeCommunicator) async {
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

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.sharedPreferencesProvider});

  final SharedPreferencesProvider sharedPreferencesProvider;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  var selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => updateNavigationRailWidth(context));
  }

  @override
  void reassemble() async {
    // Disconnect on reload
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    await appState.disconnect();

    super.reassemble();
  }

  AbstractSerial getConnector(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isEmulatedChameleon()) {
      return EmulatorSerial(log: appState.log!);
    }

    if (Platform.isMacOS) {
      return MacOSSerial(log: appState.log!);
    }

    if (Platform.isAndroid) {
      return AndroidSerial(log: appState.log!);
    }

    if (Platform.isIOS) {
      return BLESerial(log: appState.log!);
    }

    return NativeSerial(log: appState.log!);
  }

  Logger getLogger(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isDebugLogging() &&
        appState._sharedPreferencesProvider!.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(appState._sharedPreferencesProvider!),
        printer: PrettyPrinter(
          noBoxingByDefault: true,
        ),
        filter: ChameleonLogFilter(),
      );
    } else {
      return Logger();
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    appState._sharedPreferencesProvider = widget.sharedPreferencesProvider;
    appState.log ??= getLogger(appState);
    appState.connector ??= getConnector(appState);
    appState.connector!.connectionStateCallback =
        appState.onConnectorStateChanged;

    if (appState.sharedPreferencesProvider.getSideBarAutoExpansion()) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 1024) {
        appState.sharedPreferencesProvider.setSideBarExpanded(true);
      } else {
        appState.sharedPreferencesProvider.setSideBarExpanded(false);
      }
    }

    appState.devMode = appState.sharedPreferencesProvider.isDebugMode();

    Widget page; // Set Page
    if (appState.connector!.connected && appState.connector!.isDFU) {
      selectedIndex = 0;
    } else if (!appState.connector!.connected &&
        (selectedIndex == 1 ||
            selectedIndex == 2 ||
            selectedIndex == 4 ||
            selectedIndex == 9)) {
      // Reading, writing, and slot management need a connected device.
      selectedIndex = 0;
    }

    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
        if (appState.connector!.pendingConnection) {
          page = const PendingConnectionPage();
        } else {
          if (appState.connector!.connected) {
            if (appState.connector!.isDFU) {
              page = const FlashingPage();
            } else {
              page = BasicHomePage(
                onRead: () => setState(() => selectedIndex = 1),
                onWrite: () => setState(() => selectedIndex = 2),
                onAdvanced: () => setState(() => selectedIndex = 3),
                onDeviceDashboard: () => setState(() => selectedIndex = 9),
              );
            }
          } else {
            page = const ConnectPage();
          }
        }
        break;
      case 1:
        page = DeviceIoGate(
          isWrite: false,
          onDeviceDashboard: () => setState(() => selectedIndex = 9),
          child: const ReadCardPage(),
        );
        break;
      case 2:
        page = DeviceIoGate(
          isWrite: true,
          onDeviceDashboard: () => setState(() => selectedIndex = 9),
          child: const WriteCardPage(),
        );
        break;
      case 3:
        page = AdvancedPage(onSelect: (index) {
          setState(() {
            selectedIndex = index;
          });
        });
        break;
      case 4:
        page = const SlotManagerPage();
        break;
      case 5:
        page = const SavedCardsPage();
        break;
      case 6:
        page = const ToolsPage();
        break;
      case 7:
        page = const SettingsMainPage();
        break;
      case 8:
        page = const DebugPage();
        break;
      case 9:
        page = const HomePage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    try {
      WakelockPlus.toggle(enable: page is FlashingPage);
    } catch (_) {}

    return MaterialApp(
      title: 'NLC Toolkit', // App Name
      locale: widget.sharedPreferencesProvider.getLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: NlcTheme.light,
      darkTheme: NlcTheme.dark,
      themeMode: widget.sharedPreferencesProvider.getTheme(),
      home: LayoutBuilder(builder: (context, constraints) {
        final localizations = AppLocalizations.of(context)!;
        final colors = Theme.of(context).colorScheme;
        final connected = appState.connector!.connected;
        final showNavigation = !connected || !appState.connector!.isDFU;
        final compact = constraints.maxWidth < 800;
        final railExtended = constraints.maxWidth >= 1024 &&
            appState.sharedPreferencesProvider.getSideBarExpanded();
        final navigationIndex = selectedIndex <= 2 ? selectedIndex : 3;

        void selectDestination(int value) {
          if ((value == 1 || value == 2) && !connected) return;
          setState(() => selectedIndex = value);
        }

        return Scaffold(
          body: Row(
            children: [
              if (showNavigation && !compact)
                SafeArea(
                  right: false,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: colors.outline)),
                    ),
                    child: NavigationRail(
                      key: appState.navigationRailKey,
                      extended: railExtended,
                      minWidth: 76,
                      minExtendedWidth: 224,
                      groupAlignment: -0.8,
                      leading: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                'N',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (railExtended) ...[
                              const SizedBox(width: 12),
                              Text(
                                'NLC Toolkit',
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Icons.home_outlined),
                          selectedIcon: const Icon(Icons.home_rounded),
                          label: Text(localizations.home),
                        ),
                        NavigationRailDestination(
                          disabled: !connected,
                          icon: const Icon(Icons.nfc_outlined),
                          selectedIcon: const Icon(Icons.nfc_rounded),
                          label: Text(localizations.read_card),
                        ),
                        NavigationRailDestination(
                          disabled: !connected,
                          icon: const Icon(Icons.edit_outlined),
                          selectedIcon: const Icon(Icons.edit_rounded),
                          label: Text(localizations.write_card),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.grid_view_outlined),
                          selectedIcon: const Icon(Icons.grid_view_rounded),
                          label: Text(localizations.advanced),
                        ),
                      ],
                      selectedIndex: navigationIndex,
                      onDestinationSelected: selectDestination,
                    ),
                  ),
                ),
              Expanded(child: page),
            ],
          ),
          bottomNavigationBar: showNavigation && compact
              ? SafeArea(
                  top: false,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colors.outline)),
                    ),
                    child: NavigationBar(
                      height: 72,
                      selectedIndex: navigationIndex,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      onDestinationSelected: selectDestination,
                      destinations: [
                        NavigationDestination(
                          icon: const Icon(Icons.home_outlined),
                          selectedIcon: const Icon(Icons.home_rounded),
                          label: localizations.home,
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.nfc_outlined,
                              color: connected ? null : Theme.of(context).disabledColor),
                          selectedIcon: const Icon(Icons.nfc_rounded),
                          label: localizations.read_card,
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.edit_outlined,
                              color: connected ? null : Theme.of(context).disabledColor),
                          selectedIcon: const Icon(Icons.edit_rounded),
                          label: localizations.write_card,
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.grid_view_outlined),
                          selectedIcon: const Icon(Icons.grid_view_rounded),
                          label: localizations.advanced,
                        ),
                      ],
                    ),
                  ),
                )
              : const BottomProgressBar(),
        );
      }),
    );
  }
}

class BottomProgressBar extends StatelessWidget {
  const BottomProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    return (appState.connector!.connected && appState.connector!.isDFU)
        ? LinearProgressIndicator(
            value: appState.progress,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            color: Theme.of(context).colorScheme.primary,
          )
        : const SizedBox();
  }
}
