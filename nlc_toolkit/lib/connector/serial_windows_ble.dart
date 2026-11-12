import 'dart:async';
import 'dart:typed_data';

import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:universal_ble/universal_ble.dart';

/// Connexion Bluetooth (BLE) au ChameleonUltra sur les PC de bureau (Windows).
///
/// `flutter_reactive_ble` (utilisé sur mobile) ne gère pas Windows ; ce connecteur passe par
/// `universal_ble`, qui s'appuie sur le Bluetooth natif de Windows. Le Chameleon expose le service
/// Nordic UART (NUS) : on écrit les commandes sur la caractéristique RX et on reçoit les réponses
/// par notifications sur TX, comme en USB.
///
/// L'appareil doit être appairé dans les réglages Bluetooth de Windows au préalable.
class WindowsBleSerial extends AbstractSerial {
  WindowsBleSerial({required super.log});

  static const String _nusService = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String _rxCharacteristic =
      '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String _txCharacteristic =
      '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  /// Commande de salutation envoyée dès la connexion (identique à la version mobile).
  static final Uint8List _handshake = Uint8List.fromList([
    0x11,
    0xef,
    0x03,
    0xfb,
    0x00,
    0x00,
    0x00,
    0x00,
    0x02,
    0x00,
  ]);

  final Map<String, Chameleon> _found = {};
  String? _connectedId;
  bool _scanning = false;

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    // Le DFU (mise à jour du firmware) n'est pas proposé en Bluetooth sur PC pour l'instant.
    if (onlyDFU || _scanning) return [];

    _found.clear();
    _scanning = true;
    UniversalBle.onScanResult = (device) {
      final name = device.name ?? '';
      final kind = name.startsWith('ChameleonUltra')
          ? ChameleonDevice.ultra
          : name.startsWith('ChameleonLite')
          ? ChameleonDevice.lite
          : null;
      if (kind == null) return;
      _found[device.deviceId] = Chameleon(
        port: device.deviceId,
        device: kind,
        type: ConnectionType.ble,
        dfu: false,
      );
    };

    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: const [_nusService]),
      );
      await Future.delayed(const Duration(seconds: 2));
    } catch (error) {
      log.e('Recherche Bluetooth impossible : $error');
    } finally {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      UniversalBle.onScanResult = null;
      _scanning = false;
    }

    log.d('Chameleon en Bluetooth : ${_found.length}');
    return _found.values.toList();
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    final id = devicePort as String;
    await performDisconnect();
    pendingConnection = true;

    UniversalBle.onConnectionChange = (deviceId, isConnected, error) async {
      if (!isConnected && deviceId == _connectedId) {
        await performDisconnect();
      }
    };

    try {
      await UniversalBle.connect(id, timeout: const Duration(seconds: 15));
      await UniversalBle.discoverServices(id);

      UniversalBle
          .onValueChange = (deviceId, characteristicId, value, _) async {
        if (messageCallback == null) return;
        try {
          await messageCallback(Uint8List.fromList(value));
        } catch (_) {
          log.w('Donnée inattendue : ${bytesToHex(Uint8List.fromList(value))}');
        }
      };
      await UniversalBle.subscribeNotifications(
        id,
        _nusService,
        _txCharacteristic,
      );

      // Salutation : confirme que la liaison répond avant de déclarer la connexion établie.
      await UniversalBle.write(id, _nusService, _rxCharacteristic, _handshake);

      _connectedId = id;
      connected = true;
      pendingConnection = false;
      portName = id;
      device = _found[id]?.device ?? ChameleonDevice.ultra;
      activeDevicePort = id;
      connectionType = ConnectionType.ble;
      isDFU = false;
      notifyConnectionStateChanged();
      return true;
    } catch (error) {
      log.e('Connexion Bluetooth impossible : $error');
      pendingConnection = false;
      await performDisconnect();
      return false;
    }
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final id = _connectedId;
    if (id == null) return false;
    await UniversalBle.write(
      id,
      _nusService,
      _rxCharacteristic,
      command,
      withoutResponse: firmware,
    );
    return true;
  }

  @override
  Future<bool> performDisconnect() async {
    final id = _connectedId;
    final hadState = hasConnectionState || id != null;
    _connectedId = null;
    UniversalBle.onValueChange = null;
    UniversalBle.onConnectionChange = null;
    resetConnectionState();
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
    if (hadState) notifyConnectionStateChanged();
    return id != null;
  }
}
