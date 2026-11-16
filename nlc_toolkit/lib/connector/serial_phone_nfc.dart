// Connecteur « lecteur » pour la puce NFC du téléphone (mode natif). Il remplit le
// même contrat que les connecteurs série du ChameleonUltra pour que l'état connecté
// de l'app, les écrans Lire/Écrire et la récupération de clés fonctionnent sans
// changement. Les vraies entrées/sorties passent par PhoneNfcCommunicator.
import 'package:flutter/foundation.dart';

import 'package:nlc_toolkit/connector/phone_nfc.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';

class PhoneNfcSerial extends AbstractSerial {
  final PhoneNfc phoneNfc;

  PhoneNfcSerial({required super.log, PhoneNfc? phoneNfc})
      : phoneNfc = phoneNfc ?? PhoneNfc();

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    if (onlyDFU) return [];
    if (!await PhoneNfc.isAvailable()) return [];
    return const [
      Chameleon(
        port: 'phone-nfc',
        device: ChameleonDevice.ultra,
        type: ConnectionType.usb,
        dfu: false,
      ),
    ];
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    try {
      await phoneNfc.start();
    } catch (error) {
      log.e('Phone NFC start failed: $error');
      return false;
    }
    device = ChameleonDevice.ultra;
    connected = true;
    isOpen = true;
    pendingConnection = false;
    portName = 'NFC';
    connectionType = ConnectionType.usb;
    activeDevicePort = devicePort ?? 'phone-nfc';
    notifyConnectionStateChanged();
    return true;
  }

  @override
  Future<bool> performConnect() => connectSpecificDevice('phone-nfc');

  @override
  Future<bool> performDisconnect() async {
    try {
      await phoneNfc.stop();
    } catch (_) {}
    resetConnectionState();
    notifyConnectionStateChanged();
    return true;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => false;
}
