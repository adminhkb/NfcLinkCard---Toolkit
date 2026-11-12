import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:nlc_toolkit/bridge/chameleon.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/connector/serial_android.dart';
import 'package:nlc_toolkit/gui/menu/dialogs/manual_connect.dart';
import 'package:nlc_toolkit/helpers/flash.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
    this.autoScanInterval = const Duration(seconds: 3),
  });

  final Duration autoScanInterval;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  List<Chameleon> _devices = [];
  Timer? _scanTimer;
  Object? _error;
  bool _isLoading = true;
  bool _initialScanCompleted = false;
  bool _scanInProgress = false;
  bool _connectionInProgress = false;
  dynamic _connectingPort;
  bool _showedPermissionsSnackbar = false;
  dynamic _lastAutoConnectAttemptPort;

  NlcAppState get _appState =>
      Provider.of<NlcAppState>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanNow());
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  bool _shouldScan(NlcAppState appState) {
    return mounted &&
        !_connectionInProgress &&
        !appState.connector!.connected &&
        !appState.connector!.pendingConnection;
  }

  List<Chameleon> _normalizeDevices(List<Chameleon> devices) {
    final output = <Chameleon>[];
    final seen = <String>{};

    for (final device in devices) {
      final key = '${device.port}|${device.type.name}|${device.dfu}';
      if (seen.add(key)) {
        output.add(device);
      }
    }

    return output;
  }

  dynamic _firstConnectablePort(List<Chameleon> devices) {
    for (final device in devices) {
      if (!device.dfu) {
        return device.port;
      }
    }
    return null;
  }

  void _scheduleNextScan() {
    _scanTimer?.cancel();

    if (!_shouldScan(_appState) ||
        !_appState.sharedPreferencesProvider.getAutoScanEnabled()) {
      return;
    }

    _scanTimer = Timer(widget.autoScanInterval, _scanNow);
  }

  void _showPermissionsWarningIfNeeded(List<Chameleon> devices) {
    final appState = _appState;
    if (appState.connector is! AndroidSerial) {
      _showedPermissionsSnackbar = false;
      return;
    }

    final androidSerial = appState.connector as AndroidSerial;
    final shouldShow = devices.isEmpty && !androidSerial.hasAllPermissions;
    if (!shouldShow) {
      _showedPermissionsSnackbar = false;
      return;
    }

    if (_showedPermissionsSnackbar) {
      return;
    }

    _showedPermissionsSnackbar = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final localizations = AppLocalizations.of(context)!;
      final snackBar = SnackBar(
        content: Text(localizations.android_ble_permissions_missing),
        action: SnackBarAction(label: localizations.close, onPressed: () {}),
      );

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(snackBar);
    });
  }

  Future<void> _scanNow({bool manual = false}) async {
    final appState = _appState;
    if (_scanInProgress || !_shouldScan(appState)) {
      return;
    }

    _scanTimer?.cancel();

    setState(() {
      _scanInProgress = true;
      _error = null;
      if (!_initialScanCompleted || manual) {
        _isLoading = true;
      }
    });

    try {
      final devices = _normalizeDevices(
        await appState.connector!.availableChameleons(false),
      );
      if (!mounted) {
        return;
      }

      appState.syncAutoReconnectSuppression(
        devices.map((device) => device.port),
      );

      final firstConnectablePort = _firstConnectablePort(devices);
      if (firstConnectablePort != _lastAutoConnectAttemptPort) {
        _lastAutoConnectAttemptPort = null;
      }

      setState(() {
        _devices = devices;
        _isLoading = false;
        _initialScanCompleted = true;
      });

      _showPermissionsWarningIfNeeded(devices);
      await _maybeAutoConnect(devices);
    } catch (error) {
      await appState.connector!.performDisconnect();
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
        _isLoading = false;
        _initialScanCompleted = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _scanInProgress = false;
        });
        _scheduleNextScan();
      }
    }
  }

  Future<void> _maybeAutoConnect(List<Chameleon> devices) async {
    final appState = _appState;
    if (!_shouldScan(appState) ||
        !appState.sharedPreferencesProvider.getAutoConnectFirstFoundDevice()) {
      return;
    }

    Chameleon? connectableDevice;
    for (final device in devices) {
      if (!device.dfu && !appState.isAutoReconnectSuppressed(device.port)) {
        connectableDevice = device;
        break;
      }
    }

    if (connectableDevice == null) {
      _lastAutoConnectAttemptPort = null;
      return;
    }

    if (_lastAutoConnectAttemptPort == connectableDevice.port) {
      return;
    }

    _lastAutoConnectAttemptPort = connectableDevice.port;
    await _connectToDevice(connectableDevice, fromAutoConnect: true);
  }

  Future<void> _connectToDevice(
    Chameleon chameleonDevice, {
    bool fromAutoConnect = false,
  }) async {
    final appState = _appState;

    if (_connectionInProgress) {
      return;
    }

    if (chameleonDevice.dfu) {
      if (!fromAutoConnect) {
        _showDfuDialog(chameleonDevice);
      }
      return;
    }

    _scanTimer?.cancel();
    if (mounted) {
      setState(() {
        _connectionInProgress = true;
        _connectingPort = chameleonDevice.port;
      });
    }

    try {
      if (chameleonDevice.type == ConnectionType.ble) {
        appState.connector!.pendingConnection = true;
        appState.changesMade();
      }

      final connected = await appState.connector!.connectSpecificDevice(
        chameleonDevice.port,
      );
      if (connected) {
        appState.connector!.pendingConnection = false;
        appState.clearAutoReconnectSuppression(chameleonDevice.port);
        appState.communicator = ChameleonCommunicator(
          appState.log!,
          port: appState.connector,
        );
      } else {
        appState.connector!.pendingConnection = false;
      }

      appState.changesMade();
    } catch (error) {
      appState.connector!.pendingConnection = false;
      appState.changesMade();
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _connectionInProgress = false;
          _connectingPort = null;
        });
      }

      if (!appState.connector!.connected) {
        _scheduleNextScan();
      }
    }
  }

  void _showDfuDialog(Chameleon chameleonDevice) {
    final appState = _appState;
    final localizations = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(localizations.chameleon_is_dfu),
        content: Text(localizations.firmware_is_corrupted),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, localizations.cancel),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext, localizations.flash);
              appState.changesMade();

              scaffoldMessenger.hideCurrentSnackBar();
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(
                    localizations.downloading_fw(
                      chameleonDeviceName(chameleonDevice.device),
                    ),
                  ),
                  action: SnackBarAction(
                    label: localizations.close,
                    onPressed: scaffoldMessenger.hideCurrentSnackBar,
                  ),
                ),
              );

              await flashFirmware(
                appState,
                scaffoldMessenger: scaffoldMessenger,
                device: chameleonDevice.device,
                enterDFU: false,
              );

              appState.changesMade();
              if (mounted) {
                _scanNow();
              }
            },
            child: Text(localizations.flash),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(AppLocalizations localizations) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.nlc_available_devices,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            itemCount: _devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final device = _devices[index];
              final bluetooth = device.type == ConnectionType.ble;
              final connecting =
                  _connectionInProgress && _connectingPort == device.port;
              return Material(
                color: scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _connectionInProgress
                      ? null
                      : () => _connectToDevice(device),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            bluetooth
                                ? Icons.bluetooth_rounded
                                : Icons.usb_rounded,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chameleon ${chameleonDeviceName(device.device)}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                connecting
                                    ? localizations.nlc_connection_in_progress
                                    : device.port ?? '',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (device.dfu) ...[
                          const SizedBox(width: 8),
                          Text(
                            localizations.dfu,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.secondary,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        if (connecting)
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        else
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: scheme.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations localizations) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(Icons.nfc_rounded, size: 42, color: scheme.primary),
              ),
              const SizedBox(height: 22),
              Text(
                localizations.connect_no_device_title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Text(
                  Platform.isWindows
                      ? localizations.connect_no_device_description_windows
                      : localizations.connect_no_device_description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _scanInProgress
                    ? null
                    : () => _scanNow(manual: true),
                icon: _scanInProgress
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(
                  _scanInProgress
                      ? localizations.nlc_scan_in_progress
                      : localizations.connect_retry_scan,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: scheme.primary),
          const SizedBox(height: 20),
          Text(localizations.nlc_scan_in_progress),
        ],
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations localizations) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.error.withValues(alpha: 0.45)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: scheme.error, size: 42),
              const SizedBox(height: 16),
              Text(
                localizations.nlc_connection_error,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                Platform.isWindows
                    ? localizations.nlc_connection_error_description_windows
                    : localizations.nlc_connection_error_description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _error.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _scanInProgress
                    ? null
                    : () => _scanNow(manual: true),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(localizations.connect_retry_scan),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualConnectionDialog() {
    showDialog<String>(
      context: context,
      builder: (dialogContext) => const ManualConnect(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<NlcAppState>();
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 32,
                  vertical: compact ? 20 : 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NlcPageHeader(
                      eyebrow: localizations.nlc_nav_device,
                      eyebrowIcon: Icons.usb_rounded,
                      title: localizations.nlc_connect_title,
                      subtitle: Text(
                        Platform.isWindows
                            ? localizations.nlc_connect_subtitle_windows
                            : localizations.nlc_connect_subtitle,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (_devices.isNotEmpty || _error != null)
                          OutlinedButton.icon(
                            onPressed: _scanInProgress
                                ? null
                                : () => _scanNow(manual: true),
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(localizations.connect_retry_scan),
                          ),
                        if (appState.connector!.isManualConnectionSupported())
                          OutlinedButton.icon(
                            onPressed: _showManualConnectionDialog,
                            icon: const Icon(Icons.add_link_rounded),
                            label: Text(localizations.connect_manually),
                          ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Expanded(
                      child: _error != null
                          ? _buildErrorState(localizations)
                          : (_isLoading && !_initialScanCompleted)
                          ? _buildLoadingState(localizations)
                          : _devices.isEmpty
                          ? _buildEmptyState(localizations)
                          : _buildDeviceList(localizations),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
