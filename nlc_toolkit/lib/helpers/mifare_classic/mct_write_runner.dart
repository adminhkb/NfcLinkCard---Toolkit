import 'package:flutter/foundation.dart';
import 'package:nlc_toolkit/bridge/chameleon.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/mct_write.dart';

/// Keys found on the target card, like MCT's key map.
class MctKeyMap {
  final Uint8List uid;
  final MifareClassicType type;
  final Map<int, Uint8List> keyA;
  final Map<int, Uint8List> keyB;

  MctKeyMap({
    required this.uid,
    required this.type,
    Map<int, Uint8List>? keyA,
    Map<int, Uint8List>? keyB,
  }) : keyA = keyA ?? {},
       keyB = keyB ?? {};

  int get sectorCount => mfClassicGetSectorCount(type);

  bool hasAnyKey(int sector) =>
      keyA.containsKey(sector) || keyB.containsKey(sector);

  /// Keys to try for a write, key A first, as `(keyType, key)` pairs.
  List<(int, Uint8List)> keysFor(int sector) => [
    if (keyA[sector] != null) (0x60, keyA[sector]!),
    if (keyB[sector] != null) (0x61, keyB[sector]!),
  ];
}

enum MctBlockOutcome { verified, written, failed, noKey }

class MctWriteReport {
  final Map<int, MctBlockOutcome> blocks = {};

  /// The card answered with another UID, or disappeared, before a sector.
  bool cardChanged = false;

  int count(MctBlockOutcome outcome) =>
      blocks.values.where((value) => value == outcome).length;
}

/// Scans the target and finds key A and key B of every sector by trying
/// [keys] on the device, in chunks.
Future<MctKeyMap?> mctMapKeys(
  ChameleonCommunicator communicator,
  List<Uint8List> keys, {
  required int chunkSize,
  void Function(double progress)? onProgress,
}) async {
  if (!await communicator.isReaderDeviceMode()) {
    await communicator.setReaderDeviceMode(true);
  }
  final card = await communicator.scan14443aTag();
  if (card == null || !await communicator.detectMf1Support()) return null;

  final map = MctKeyMap(
    uid: Uint8List.fromList(card.uid),
    type: await mfClassicGetType(communicator),
  );
  final steps = map.sectorCount * 2;
  for (var sector = 0; sector < map.sectorCount; sector++) {
    final trailer = mfClassicGetSectorTrailerBlockBySector(sector);
    for (final keyType in [0x60, 0x61]) {
      for (var start = 0; start < keys.length; start += chunkSize) {
        final end = start + chunkSize > keys.length
            ? keys.length
            : start + chunkSize;
        final found = await communicator.mf1AuthMultipleKeys(
          trailer,
          keyType,
          keys.sublist(start, end),
        );
        if (found != null && found.length == 6) {
          (keyType == 0x60 ? map.keyA : map.keyB)[sector] = found;
          break;
        }
      }
      onProgress?.call((sector * 2 + (keyType - 0x60) + 1) / steps);
    }
  }
  return map;
}

Future<bool> _sameCard(ChameleonCommunicator communicator, Uint8List uid) async {
  final card = await communicator.scan14443aTag();
  return card != null && listEquals(card.uid, uid);
}

/// Writes [plan] with the keys of [keyMap]. Data blocks are read back with
/// the key that wrote them. Trailers are not read back: the card hides key A.
Future<MctWriteReport> mctRunWritePlan(
  ChameleonCommunicator communicator,
  MctWritePlan plan,
  MctKeyMap keyMap, {
  void Function(double progress)? onProgress,
}) async {
  final report = MctWriteReport();
  final total = plan.blockCount;
  var done = 0;

  for (final entry in plan.blocksBySector.entries) {
    final sector = entry.key;
    if (!await _sameCard(communicator, keyMap.uid)) {
      report.cardChanged = true;
      return report;
    }
    final keys = keyMap.keysFor(sector);
    for (final block in entry.value) {
      if (keys.isEmpty) {
        report.blocks[block.block] = MctBlockOutcome.noKey;
      } else {
        report.blocks[block.block] = MctBlockOutcome.failed;
        for (final (keyType, key) in keys) {
          if (!await communicator.mf1WriteBlock(
            block.block,
            keyType,
            key,
            block.data,
          )) {
            continue;
          }
          var outcome = MctBlockOutcome.written;
          if (!block.isTrailer) {
            try {
              final readback = await communicator.mf1ReadBlock(
                block.block,
                keyType,
                key,
              );
              if (listEquals(readback, block.data)) {
                outcome = MctBlockOutcome.verified;
              }
            } catch (_) {}
          }
          report.blocks[block.block] = outcome;
          break;
        }
      }
      done++;
      onProgress?.call(total == 0 ? 1 : done / total);
    }
  }
  return report;
}

/// MCT's "Increment/decrement value block": applies the operation on the
/// card and transfers the result back into the same block.
Future<bool> mctChangeValueBlock(
  ChameleonCommunicator communicator,
  MctKeyMap keyMap,
  int block,
  MifareClassicValueBlockOperator operator,
  int amount,
) async {
  if (!await _sameCard(communicator, keyMap.uid)) return false;
  for (final (keyType, key) in keyMap.keysFor(
    mfClassicGetSectorByBlock(block),
  )) {
    if (await communicator.manipulateValueBlock(
      block,
      keyType,
      key,
      operator,
      amount,
      block,
      keyType,
      key,
    )) {
      return true;
    }
  }
  return false;
}
