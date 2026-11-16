// Communicator qui parle à la puce NFC du téléphone au lieu d'un ChameleonUltra.
// Il hérite de ChameleonCommunicator et redéfinit uniquement les commandes HF
// (haute fréquence, 13,56 MHz) utilisées par la lecture/écriture : scan, MIFARE
// Classic (auth/lecture/écriture) et échange brut ISO14443-A pour Ultralight/NTAG.
//
// Ainsi tout le pipeline existant (readHFInfo, performMifareClassicScan, la
// récupération de clés par dictionnaire, le dump, l'écriture) fonctionne tel quel
// quand `appState.communicator` pointe sur cette classe.
//
// Limites matérielles d'un téléphone, assumées : pas de cassage de clé inconnue
// (nested/darkside) et pas de 125 kHz. Ces commandes échouent proprement, ce qui
// laisse simplement les secteurs sans clé connue vides — « tout, quitte à échouer ».
import 'dart:typed_data';

import 'package:nlc_toolkit/bridge/chameleon.dart';
import 'package:nlc_toolkit/connector/phone_nfc.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';

class PhoneNfcCommunicator extends ChameleonCommunicator {
  final PhoneNfc phoneNfc;
  PhoneNfcCard? _card;

  PhoneNfcCommunicator(super.log, {PhoneNfc? phoneNfc})
      : phoneNfc = phoneNfc ?? PhoneNfc();

  Future<PhoneNfcCard?> _ensureCard() async {
    _card ??= await phoneNfc.getCard();
    return _card;
  }

  @override
  Future<bool> isReaderDeviceMode() async => true;

  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {}

  @override
  Future<CardData?> scan14443aTag() async {
    final card = await phoneNfc.getCard();
    _card = card;
    if (card == null || card.uid.isEmpty) return null;
    return CardData(
      uid: card.uid,
      sak: card.sak,
      atqa: card.atqa,
      ats: card.ats,
    );
  }

  @override
  Future<bool> detectMf1Support() async {
    final card = await _ensureCard();
    return card?.hasMifareClassic ?? false;
  }

  @override
  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async {
    try {
      return await phoneNfc.mfcAuth(block, keyType, key);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> mf1AuthMultipleKeys(
      int block, int keyType, List<Uint8List> keys) async {
    for (final key in keys) {
      try {
        if (await phoneNfc.mfcAuth(block, keyType, key)) {
          return Uint8List.fromList(key);
        }
      } catch (_) {
        // clé suivante
      }
    }
    return null;
  }

  @override
  Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key) async {
    return await phoneNfc.mfcReadBlock(block, keyType, key);
  }

  @override
  Future<bool> mf1WriteBlock(
      int block, int keyType, Uint8List key, Uint8List data) async {
    try {
      return await phoneNfc.mfcWriteBlock(block, keyType, key, data);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> send14ARaw(Uint8List data,
      {int respTimeoutMs = 100,
      int? bitLen,
      bool activateRfField = true,
      bool waitResponse = true,
      bool appendCrc = true,
      bool autoSelect = true,
      bool keepRfField = false,
      bool checkResponseCrc = true}) async {
    final card = await _ensureCard();

    // Carte MIFARE Classic : la puce du téléphone gère le crypto1 en interne, on
    // ne peut pas envoyer de commande brute. On émule juste la détection de taille
    // de mfClassicGetType ([0x60, bloc]) à partir du nombre de blocs réel.
    if (card != null && card.hasMifareClassic) {
      if (data.length == 2 && data[0] == 0x60) {
        final block = data[1];
        if (card.mifareClassicBlockCount > 0 &&
            block < card.mifareClassicBlockCount) {
          return Uint8List(4); // réponse « bloc présent »
        }
      }
      return Uint8List(0);
    }

    // Autres tags (Ultralight/NTAG) : échange brut réel via NfcA.
    try {
      return await phoneNfc.transceive(data);
    } catch (_) {
      // Un NAK / une absence de réponse correspond à un retour vide côté Chameleon.
      return Uint8List(0);
    }
  }

  // --- Compatibilité d'appareil : on se présente comme un lecteur HF complet. ---

  @override
  Future<FirmwareVersion> getFirmwareVersion() async =>
      FirmwareVersion(legacyProtocol: false, version: 999);

  @override
  Future<List<int>> getDeviceCapabilities() async => [
        ChameleonCommand.getDeviceMode.value,
        ChameleonCommand.changeDeviceMode.value,
        ChameleonCommand.scan14ATag.value,
        ChameleonCommand.hf14ARawCommand.value,
        ChameleonCommand.mf1SupportDetect.value,
        ChameleonCommand.mf1CheckKey.value,
        ChameleonCommand.mf1ReadBlock.value,
        ChameleonCommand.mf1WriteBlock.value,
      ];

  // --- Commandes impossibles sur téléphone : échec net (récupération de clé, LF). ---

  @override
  Future<NTLevel> getMf1NTLevel() async => NTLevel.unknown;

  @override
  Future<DarksideResult> checkMf1Darkside() async =>
      throw UnsupportedError('Key recovery not supported on phone NFC');
}
