// Connexion du lecteur directement dans la carte « Appareil » de l'accueil, en mode simple :
// on recherche les ChameleonUltra branchés et on s'y connecte sans ouvrir d'onglet dédié.
// Version compacte de la page de connexion (gui/page/connect.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nlc_toolkit/bridge/chameleon.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/main.dart';

class InlineDeviceConnect extends StatefulWidget {
  const InlineDeviceConnect({
    super.key,
    this.autoScanInterval = const Duration(seconds: 3),
  });

  final Duration autoScanInterval;

  @override
  State<InlineDeviceConnect> createState() => _InlineDeviceConnectState();
}

class _InlineDeviceConnectState extends State<InlineDeviceConnect> {
  List<Chameleon> _devices = [];
  Timer? _scanTimer;
  Object? _error;
  bool _initialScanCompleted = false;
  bool _scanInProgress = false;
  bool _connectionInProgress = false;
  dynamic _connectingPort;
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

  bool _shouldScan(NlcAppState appState) =>
      mounted &&
      !_connectionInProgress &&
      !appState.connector!.connected &&
      !appState.connector!.pendingConnection;

  List<Chameleon> _normalize(List<Chameleon> devices) {
    final output = <Chameleon>[];
    final seen = <String>{};
    for (final device in devices) {
      final key = '${device.port}|${device.type.name}|${device.dfu}';
      if (seen.add(key)) output.add(device);
    }
    return output;
  }

  void _scheduleNextScan() {
    _scanTimer?.cancel();
    if (!_shouldScan(_appState) ||
        !_appState.sharedPreferencesProvider.getAutoScanEnabled()) {
      return;
    }
    _scanTimer = Timer(widget.autoScanInterval, _scanNow);
  }

  Future<void> _scanNow({bool manual = false}) async {
    final appState = _appState;
    if (_scanInProgress || !_shouldScan(appState)) return;
    _scanTimer?.cancel();
    setState(() {
      _scanInProgress = true;
      _error = null;
    });
    try {
      final devices = _normalize(
        await appState.connector!.availableChameleons(false),
      );
      if (!mounted) return;
      appState.syncAutoReconnectSuppression(devices.map((d) => d.port));
      final firstConnectable = devices
          .where((d) => !d.dfu)
          .map((d) => d.port)
          .firstOrNull;
      if (firstConnectable != _lastAutoConnectAttemptPort) {
        _lastAutoConnectAttemptPort = null;
      }
      setState(() {
        _devices = devices;
        _initialScanCompleted = true;
      });
      await _maybeAutoConnect(devices);
    } catch (error) {
      await appState.connector!.performDisconnect();
      if (!mounted) return;
      setState(() {
        _error = error;
        _initialScanCompleted = true;
      });
    } finally {
      if (mounted) {
        setState(() => _scanInProgress = false);
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
    Chameleon? connectable;
    for (final device in devices) {
      if (!device.dfu && !appState.isAutoReconnectSuppressed(device.port)) {
        connectable = device;
        break;
      }
    }
    if (connectable == null) {
      _lastAutoConnectAttemptPort = null;
      return;
    }
    if (_lastAutoConnectAttemptPort == connectable.port) return;
    _lastAutoConnectAttemptPort = connectable.port;
    await _connectToDevice(connectable);
  }

  Future<void> _connectToDevice(Chameleon device) async {
    final appState = _appState;
    if (_connectionInProgress || device.dfu) return;
    _scanTimer?.cancel();
    if (mounted) {
      setState(() {
        _connectionInProgress = true;
        _connectingPort = device.port;
      });
    }
    try {
      if (device.type == ConnectionType.ble) {
        appState.connector!.pendingConnection = true;
        appState.changesMade();
      }
      final connected = await appState.connector!.connectSpecificDevice(
        device.port,
      );
      if (connected) {
        appState.connector!.pendingConnection = false;
        appState.clearAutoReconnectSuppression(device.port);
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
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _connectionInProgress = false;
          _connectingPort = null;
        });
      }
      if (!appState.connector!.connected) _scheduleNextScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final french = Localizations.localeOf(context).languageCode == 'fr';
    final devices = _devices.where((d) => !d.dfu).toList();
    final scanning = _scanInProgress && !_initialScanCompleted;

    if (_error != null) {
      return _Shell(
        children: [
          Text(
            french ? 'Connexion impossible' : 'Connection failed',
            style: const TextStyle(
              color: Nlc.rose300,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _scanButton(l, french),
        ],
      );
    }

    if (devices.isEmpty) {
      return _Shell(
        children: [
          Row(
            children: [
              if (scanning)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.usb_off_rounded, color: Nlc.slate400),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  scanning
                      ? (french ? 'Recherche d\'un lecteur…' : 'Looking for a reader…')
                      : (french
                            ? 'Aucun lecteur trouvé. Branchez votre ChameleonUltra.'
                            : 'No reader found. Plug in your ChameleonUltra.'),
                  style: const TextStyle(color: Nlc.slate400, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _scanButton(l, french),
        ],
      );
    }

    return _Shell(
      children: [
        for (final device in devices) ...[
          _DeviceRow(
            device: device,
            connecting: _connectionInProgress && _connectingPort == device.port,
            busy: _connectionInProgress,
            onTap: () => _connectToDevice(device),
          ),
          const SizedBox(height: 8),
        ],
        _scanButton(l, french),
      ],
    );
  }

  Widget _scanButton(AppLocalizations l, bool french) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _scanInProgress ? null : () => _scanNow(manual: true),
      icon: _scanInProgress
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(french ? 'Rechercher' : 'Scan'),
    ),
  );
}

class _Shell extends StatelessWidget {
  const _Shell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.connecting,
    required this.busy,
    required this.onTap,
  });

  final Chameleon device;
  final bool connecting;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final bluetooth = device.type == ConnectionType.ble;
    return Material(
      color: Nlc.slate900,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Nlc.violet500.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  bluetooth ? Icons.bluetooth_rounded : Icons.usb_rounded,
                  color: Nlc.violet300,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chameleon ${chameleonDeviceName(device.device)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Nlc.slate100,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      connecting
                          ? l.nlc_connection_in_progress
                          : (device.port?.toString() ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Nlc.slate500, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (connecting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Nlc.violet300,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
