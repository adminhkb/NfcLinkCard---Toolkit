// Accès à la puce NFC du téléphone (mode « natif »), via le MethodChannel natif
// `nlc/phone_nfc` (voir android/.../PhoneNfcManager.kt). Sert de base au
// PhoneNfcCommunicator, qui imite l'interface du ChameleonUltra pour que tout le
// code de lecture/écriture existant fonctionne sans changement.
import 'package:flutter/services.dart';

/// Infos de base lues sur le tag présent devant le téléphone.
class PhoneNfcCard {
  final Uint8List uid;
  final Uint8List atqa;
  final int sak;
  final Uint8List ats;
  final List<String> techs;
  final int mifareClassicBlockCount;

  PhoneNfcCard({
    required this.uid,
    required this.atqa,
    required this.sak,
    required this.ats,
    required this.techs,
    required this.mifareClassicBlockCount,
  });

  bool get hasMifareClassic =>
      techs.any((t) => t.endsWith('MifareClassic'));
}

/// Fin façade Dart autour du MethodChannel natif.
class PhoneNfc {
  static const MethodChannel _channel = MethodChannel('nlc/phone_nfc');

  /// Vrai si le téléphone a une puce NFC activée.
  static Future<bool> isAvailable() async {
    try {
      return (await _channel.invokeMethod<bool>('isAvailable')) ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Active le mode lecteur : le téléphone attend un tag.
  Future<void> start() => _channel.invokeMethod<void>('start');

  /// Désactive le mode lecteur.
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Uint8List _toBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List) {
      return Uint8List.fromList(value.map((e) => (e as num).toInt()).toList());
    }
    return Uint8List(0);
  }

  /// Renvoie le tag présent, ou `null` si aucun n'est détecté.
  Future<PhoneNfcCard?> getCard() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('getCard');
    if (map == null) return null;
    return PhoneNfcCard(
      uid: _toBytes(map['uid']),
      atqa: _toBytes(map['atqa']),
      sak: (map['sak'] as num?)?.toInt() ?? 0,
      ats: _toBytes(map['ats']),
      techs: (map['techs'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      mifareClassicBlockCount: (map['mfcBlockCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Authentifie un secteur MIFARE Classic (keyType 0x60 = A, 0x61 = B).
  Future<bool> mfcAuth(int block, int keyType, Uint8List key) async {
    return (await _channel.invokeMethod<bool>('mfcAuth', {
          'block': block,
          'keyType': keyType,
          'key': key,
        })) ??
        false;
  }

  Future<Uint8List> mfcReadBlock(int block, int keyType, Uint8List key) async {
    final res = await _channel.invokeMethod('mfcReadBlock', {
      'block': block,
      'keyType': keyType,
      'key': key,
    });
    return _toBytes(res);
  }

  Future<bool> mfcWriteBlock(
      int block, int keyType, Uint8List key, Uint8List data) async {
    return (await _channel.invokeMethod<bool>('mfcWriteBlock', {
          'block': block,
          'keyType': keyType,
          'key': key,
          'data': data,
        })) ??
        false;
  }

  /// Échange ISO14443-A brut (CRC géré par le contrôleur). Utilisé pour
  /// Ultralight/NTAG.
  Future<Uint8List> transceive(Uint8List data) async {
    final res = await _channel.invokeMethod('transceive', {'data': data});
    return _toBytes(res);
  }
}
