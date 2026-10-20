import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/dialogs/chameleon_settings.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/component/slot_changer.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int selectedSlot = 1;
  bool isLegacyFirmware = false;

  @override
  void initState() {
    super.initState();
  }

  Future<((Icon, BatteryCharge), String, List<String>, bool, bool)>
  getFutureData() async {
    var appState = context.read<ChameleonGUIState>();
    List<SlotTypes> slotTypes = [];
    try {
      slotTypes = await appState.communicator!.getSlotTagTypes();
    } catch (e) {
      appState.log!.e(e);
    }

    return (
      await getBatteryInfo(),
      await getUsedSlotsOut8(slotTypes),
      await getVersion(),
      await isReaderDeviceMode(),
      await areCapabilitiesSupported(),
    );
  }

  Future<bool> areCapabilitiesSupported() async {
    // Checks that firmware supports all functions of current app
    // If not, prompt user to update firmware (as outdated firmware might break app)

    int ultraCapability = ChameleonCommand.mf0UlcAuth.value;
    int liteCapability = ChameleonCommand.setIdteckEmulatorID.value;

    var appState = context.read<ChameleonGUIState>();
    List<int> capabilities;
    try {
      capabilities = await appState.communicator!.getDeviceCapabilities();
    } catch (_) {
      return false;
    }

    if (appState.connector!.device == ChameleonDevice.ultra &&
        !capabilities.contains(ultraCapability)) {
      return false;
    }

    if (appState.connector!.device == ChameleonDevice.lite &&
        !capabilities.contains(liteCapability)) {
      return false;
    }

    return true;
  }

  Future<(Icon, BatteryCharge)> getBatteryInfo() async {
    var appState = context.read<ChameleonGUIState>();
    var icon = const Icon(Icons.battery_unknown);
    BatteryCharge battery = BatteryCharge(percent: 0, voltage: 0);

    try {
      battery = await appState.communicator!.getBatteryCharge();
    } catch (_) {}

    if (battery.percent > 98) {
      icon = const Icon(Icons.battery_full);
    } else if (battery.percent > 87) {
      icon = const Icon(Icons.battery_6_bar);
    } else if (battery.percent > 75) {
      icon = const Icon(Icons.battery_5_bar);
    } else if (battery.percent > 62) {
      icon = const Icon(Icons.battery_4_bar);
    } else if (battery.percent > 50) {
      icon = const Icon(Icons.battery_3_bar);
    } else if (battery.percent > 37) {
      icon = const Icon(Icons.battery_2_bar);
    } else if (battery.percent > 10) {
      icon = const Icon(Icons.battery_1_bar);
    } else if (battery.percent > 3) {
      icon = const Icon(Icons.battery_0_bar);
    } else if (battery.percent > 0) {
      icon = const Icon(Icons.battery_alert);
    }

    return (icon, battery);
  }

  Future<String> getUsedSlotsOut8(List<SlotTypes> slotTypes) async {
    int usedSlotsOut8 = 0;

    if (slotTypes.isEmpty) {
      return AppLocalizations.of(context)!.unknown;
    }

    for (int i = 0; i < 8; i++) {
      if (slotTypes[i].notMatch()) {
        usedSlotsOut8++;
      }
    }
    return usedSlotsOut8.toString();
  }

  Future<List<String>> getVersion() async {
    var appState = context.read<ChameleonGUIState>();

    String commitHash = "";
    var firmware = await appState.communicator!.getFirmwareVersion();
    isLegacyFirmware = firmware.legacyProtocol;
    String firmwareVersion = numToVerCode(firmware.version);

    try {
      commitHash = await appState.communicator!.getGitCommitHash();
    } catch (_) {}

    if (commitHash.isEmpty) {
      if (mounted) {
        commitHash = AppLocalizations.of(context)!.outdated_fw;
      } else {
        commitHash = "Outdated FW";
      }
    }

    if (mounted && isLegacyFirmware) {
      var localizations = AppLocalizations.of(context)!;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(localizations.outdated_protocol),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(localizations.outdated_protocol_description_1),
                  Text(localizations.outdated_protocol_description_2),
                  Text(localizations.outdated_protocol_description_3),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(localizations.update),
                onPressed: () async {
                  Navigator.of(context).pop();
                  var localizations = AppLocalizations.of(context)!;
                  var scaffoldMessenger = ScaffoldMessenger.of(context);
                  var snackBar = SnackBar(
                    content: Text(
                      localizations.downloading_fw(
                        chameleonDeviceName(appState.connector!.device),
                      ),
                    ),
                    action: SnackBarAction(
                      label: localizations.close,
                      onPressed: () {
                        scaffoldMessenger.hideCurrentSnackBar();
                      },
                    ),
                  );

                  scaffoldMessenger.showSnackBar(snackBar);
                  await flashFirmware(
                    appState,
                    scaffoldMessenger: scaffoldMessenger,
                  );
                },
              ),
              TextButton(
                child: Text(localizations.skip),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }

    return ["$firmwareVersion ($commitHash)", commitHash];
  }

  Future<bool> isReaderDeviceMode() async {
    var appState = context.read<ChameleonGUIState>();
    return await appState.communicator!.isReaderDeviceMode();
  }

  Future<void> _checkFirmwareUpdates(List<String> fwVersion) async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    String latestCommit;

    try {
      latestCommit = await latestAvailableCommit(appState.connector!.device);
    } catch (error) {
      if (!mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('${localizations.update_error}: $error'),
          action: SnackBarAction(label: localizations.close, onPressed: () {}),
        ),
      );
      return;
    }

    try {
      fwVersion[1] = await resolveCommit(fwVersion[1]);
    } catch (_) {}

    appState.log!.i(
      'Latest commit: $latestCommit, current commit ${fwVersion[1]}',
    );
    if (latestCommit.isEmpty || !mounted) return;

    if (latestCommit.startsWith(fwVersion[1])) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            localizations.up_to_date(
              chameleonDeviceName(appState.connector!.device),
            ),
          ),
          action: SnackBarAction(label: localizations.close, onPressed: () {}),
        ),
      );
      return;
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          localizations.downloading_fw(
            chameleonDeviceName(appState.connector!.device),
          ),
        ),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: () => scaffoldMessenger.hideCurrentSnackBar(),
        ),
      ),
    );
    try {
      await flashFirmware(appState, scaffoldMessenger: scaffoldMessenger);
    } catch (error) {
      if (!mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('${localizations.update_error}: $error'),
          action: SnackBarAction(
            label: localizations.close,
            onPressed: () => scaffoldMessenger.hideCurrentSnackBar(),
          ),
        ),
      );
    }
  }

  Future<void> _updateFirmware() async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          localizations.downloading_fw(
            chameleonDeviceName(appState.connector!.device),
          ),
        ),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: () => scaffoldMessenger.hideCurrentSnackBar(),
        ),
      ),
    );
    await flashFirmware(appState, scaffoldMessenger: scaffoldMessenger);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;

    return FutureBuilder(
      future: getFutureData(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text(localizations.device_dashboard)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          appState.disconnect();
          return Scaffold(
            appBar: AppBar(title: Text(localizations.device_dashboard)),
            body: Center(
              child: ErrorPage(errorMessage: snapshot.error.toString()),
            ),
          );
        }

        final (
          batteryInfo,
          usedSlots,
          fwVersion,
          isReaderDeviceMode,
          areCapabilitiesSupported,
        ) = snapshot.data;
        final connector = appState.connector!;
        final colors = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final isDemo = connector.portName == 'Demo';
        final deviceName = 'Chameleon ${chameleonDeviceName(connector.device)}';

        Widget panel(Widget child, {Color? color}) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            color: color,
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          );
        }

        Widget devicePanel(bool compact) {
          return panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceName,
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            connector.portName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    connector.connectionType ==
                                            ConnectionType.ble
                                        ? Icons.bluetooth_rounded
                                        : Icons.usb_rounded,
                                    size: 16,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    connector.connectionType ==
                                            ConnectionType.ble
                                        ? 'Bluetooth'
                                        : 'USB',
                                    style: textTheme.labelMedium?.copyWith(
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Image.asset(
                      connector.device == ChameleonDevice.ultra
                          ? 'assets/black-ultra-standing-front.webp'
                          : 'assets/black-lite-standing-front.webp',
                      width: compact ? 86 : 132,
                      height: compact ? 128 : 176,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget slotsPanel() {
          return panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.grid_view_rounded, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        localizations.used_slots,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$usedSlots/8',
                      style: textTheme.titleLarge?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const FittedBox(
                  alignment: Alignment.center,
                  fit: BoxFit.scaleDown,
                  child: SlotChanger(),
                ),
              ],
            ),
          );
        }

        Widget connectionPanel() {
          return panel(
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF4ED1A1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    localizations.chameleon_connected,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  connector.connectionType == ConnectionType.ble
                      ? Icons.bluetooth_rounded
                      : Icons.usb_rounded,
                ),
              ],
            ),
          );
        }

        Widget batteryPanel() {
          final percent = batteryInfo.$2.percent;
          final voltage = batteryInfo.$2.voltage;
          return panel(
            Tooltip(
              message: localizations.battery_info(percent, voltage),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      batteryInfo.$1,
                      const SizedBox(width: 10),
                      Text(
                        '$percent%',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$voltage mV',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (percent.clamp(0, 100) as num).toDouble() / 100,
                    color: percent > 20
                        ? const Color(0xFF4ED1A1)
                        : colors.error,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ],
              ),
            ),
          );
        }

        Widget firmwarePanel() {
          if (isDemo) return const SizedBox.shrink();
          return panel(
            Row(
              children: [
                Icon(Icons.memory_rounded, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.firmware_version,
                        style: textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fwVersion[0],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _checkFirmwareUpdates(fwVersion),
                  tooltip: localizations.check_updates,
                  icon: const Icon(Icons.system_update_alt_rounded),
                ),
              ],
            ),
          );
        }

        Widget actionsPanel() {
          return panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  localizations.device_dashboard_description,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await appState.communicator!.setReaderDeviceMode(
                          !isReaderDeviceMode,
                        );
                        if (!mounted) return;
                        setState(() {});
                        appState.changesMade();
                      },
                      icon: Icon(
                        isReaderDeviceMode
                            ? Icons.nfc_rounded
                            : Icons.barcode_reader,
                      ),
                      label: Text(
                        isReaderDeviceMode
                            ? localizations.emulator_mode
                            : localizations.reader_mode,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showDialog<String>(
                        context: context,
                        builder: (dialogContext) => const ChameleonSettings(),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(localizations.settings),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget warningPanel(String message, {VoidCallback? action}) {
          return panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colors.error),
                    const SizedBox(width: 12),
                    Expanded(child: Text(message)),
                  ],
                ),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: action,
                      child: Text(localizations.update),
                    ),
                  ),
                ],
              ],
            ),
            color: colors.errorContainer,
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('NLC Toolkit'),
            actions: [
              IconButton(
                onPressed: () => appState.disconnect(manual: true),
                tooltip: localizations.disconnect_device,
                icon: const Icon(Icons.link_off_rounded),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 840;
              return SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          localizations.device_dashboard,
                          style: textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          localizations.device_dashboard_description,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (isDemo) warningPanel(localizations.demo_firmware),
                        if (!areCapabilitiesSupported && !isDemo)
                          warningPanel(
                            localizations.please_update_firmware,
                            action: _updateFirmware,
                          ),
                        if (compact) ...[
                          devicePanel(true),
                          connectionPanel(),
                          batteryPanel(),
                          slotsPanel(),
                          firmwarePanel(),
                          actionsPanel(),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [devicePanel(false), slotsPanel()],
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    connectionPanel(),
                                    batteryPanel(),
                                    firmwarePanel(),
                                    actionsPanel(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
