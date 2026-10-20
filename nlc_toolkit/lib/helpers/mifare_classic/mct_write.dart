import 'dart:typed_data';

import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/dump_analyzer.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';

/// Access condition bytes 6-9 of a factory MIFARE Classic sector trailer.
final mfClassicFactoryAccessConditions = Uint8List.fromList([
  0xFF,
  0x07,
  0x80,
  0x69,
]);

/// Key A FFFFFFFFFFFF, access conditions FF078069, key B FFFFFFFFFFFF.
final mfClassicFactoryTrailer = Uint8List.fromList([
  ...List.filled(6, 0xFF),
  ...mfClassicFactoryAccessConditions,
  ...List.filled(6, 0xFF),
]);

/// True when bytes 6-8 of a trailer hold consistent access conditions.
/// Writing inconsistent bits makes the sector permanently unusable.
bool mfClassicAccessConditionsValid(Uint8List acBytes) =>
    acBytes.length >= 3 &&
    MifareClassicDumpAnalyzer.accessConditionValues(
          bytesToHex(acBytes.sublist(0, 3)),
        ) !=
        null;

/// True when [block0] can be written as a manufacturer block for a UID of
/// [uidLength] bytes. A 4-byte UID must be followed by its BCC, otherwise the
/// card stops answering anticollision.
bool mfClassicManufacturerBlockValid(Uint8List block0, int uidLength) {
  if (block0.length != 16) return false;
  if (uidLength != 4) return true;
  return block0[4] == calculateBcc(block0.sublist(0, 4));
}

class MctWriteBlock {
  final int block;
  final Uint8List data;
  final bool isTrailer;

  const MctWriteBlock(this.block, this.data, {this.isTrailer = false});
}

class MctWriteOptions {
  /// Sectors to write. Sectors without data in the dump are ignored.
  final Set<int> sectors;

  /// Also write block 0. Only CUID/Gen2 cards accept it.
  final bool writeManufacturerBlock;

  /// Write sector trailers (keys and access conditions).
  final bool writeTrailers;

  /// Replaces bytes 6-9 of every trailer, like MCT's static access
  /// conditions option. Null keeps the dump's own bytes.
  final Uint8List? staticAccessConditions;

  const MctWriteOptions({
    required this.sectors,
    this.writeManufacturerBlock = false,
    this.writeTrailers = true,
    this.staticAccessConditions,
  });
}

class MctWritePlan {
  /// Blocks to write per sector, data blocks first and the trailer last,
  /// because writing the trailer can change the keys of the sector.
  final Map<int, List<MctWriteBlock>> blocksBySector;

  /// Sectors whose trailer is skipped because its access conditions are
  /// invalid.
  final List<int> invalidTrailerSectors;

  /// True when block 0 was requested but is missing or has a wrong BCC.
  final bool invalidManufacturerBlock;

  const MctWritePlan({
    required this.blocksBySector,
    this.invalidTrailerSectors = const [],
    this.invalidManufacturerBlock = false,
  });

  int get blockCount =>
      blocksBySector.values.fold(0, (sum, blocks) => sum + blocks.length);
}

/// Sectors of [card] that contain at least one readable block.
List<int> mctSectorsWithData(CardSave card) {
  final type = chameleonTagTypeGetMfClassicType(card.tag);
  final sectors = <int>[];
  for (var sector = 0; sector < mfClassicGetSectorCount(type); sector++) {
    final first = mfClassicGetFirstBlockCountBySector(sector);
    final count = mfClassicGetBlockCountBySector(sector);
    for (var block = first; block < first + count; block++) {
      if (block < card.data.length && card.data[block].length == 16) {
        sectors.add(sector);
        break;
      }
    }
  }
  return sectors;
}

/// Builds the blocks MCT's "Write dump" would write for [card].
MctWritePlan buildMctDumpWritePlan(CardSave card, MctWriteOptions options) {
  final staticAc = options.staticAccessConditions;
  if (staticAc != null &&
      (staticAc.length != 4 || !mfClassicAccessConditionsValid(staticAc))) {
    throw ArgumentError.value(staticAc, 'staticAccessConditions');
  }

  final blocksBySector = <int, List<MctWriteBlock>>{};
  final invalidTrailers = <int>[];
  var invalidBlock0 = false;

  for (final sector in mctSectorsWithData(card)) {
    if (!options.sectors.contains(sector)) continue;
    final first = mfClassicGetFirstBlockCountBySector(sector);
    final trailerBlock = mfClassicGetSectorTrailerBlockBySector(sector);
    final blocks = <MctWriteBlock>[];

    for (var block = first; block < trailerBlock; block++) {
      if (block >= card.data.length || card.data[block].length != 16) {
        continue;
      }
      if (block == 0) {
        if (!options.writeManufacturerBlock) continue;
        if (!mfClassicManufacturerBlockValid(
          card.data[0],
          hexToBytes(card.uid).length,
        )) {
          invalidBlock0 = true;
          continue;
        }
      }
      blocks.add(MctWriteBlock(block, Uint8List.fromList(card.data[block])));
    }

    if (options.writeTrailers &&
        trailerBlock < card.data.length &&
        card.data[trailerBlock].length == 16) {
      final trailer = Uint8List.fromList(card.data[trailerBlock]);
      if (staticAc != null) trailer.setRange(6, 10, staticAc);
      if (mfClassicAccessConditionsValid(trailer.sublist(6, 9))) {
        blocks.add(MctWriteBlock(trailerBlock, trailer, isTrailer: true));
      } else {
        invalidTrailers.add(sector);
      }
    }

    if (blocks.isNotEmpty) blocksBySector[sector] = blocks;
  }

  return MctWritePlan(
    blocksBySector: blocksBySector,
    invalidTrailerSectors: invalidTrailers,
    invalidManufacturerBlock: invalidBlock0,
  );
}

enum MctBlockRejection {
  manufacturerBlockLocked,
  invalidManufacturerBlock,
  invalidAccessConditions,
}

/// Checks a single-block write like MCT's "Write block": block 0 needs the
/// manufacturer option and a valid BCC, a trailer needs valid access
/// conditions. Returns null when the write is allowed.
MctBlockRejection? mctCheckBlockWrite(
  int block,
  Uint8List data, {
  required bool allowManufacturerBlock,
  required int uidLength,
}) {
  if (block == 0) {
    if (!allowManufacturerBlock) {
      return MctBlockRejection.manufacturerBlockLocked;
    }
    if (!mfClassicManufacturerBlockValid(data, uidLength)) {
      return MctBlockRejection.invalidManufacturerBlock;
    }
  }
  final sector = mfClassicGetSectorByBlock(block);
  if (block == mfClassicGetSectorTrailerBlockBySector(sector) &&
      !mfClassicAccessConditionsValid(data.sublist(6, 9))) {
    return MctBlockRejection.invalidAccessConditions;
  }
  return null;
}

/// Builds MCT's "Format a tag (factory format)": every data block except
/// block 0 becomes 00 and every trailer gets the factory keys and access
/// conditions.
MctWritePlan buildFactoryFormatPlan(Iterable<int> sectors) {
  final blocksBySector = <int, List<MctWriteBlock>>{};
  for (final sector in sectors) {
    final first = mfClassicGetFirstBlockCountBySector(sector);
    final trailerBlock = mfClassicGetSectorTrailerBlockBySector(sector);
    blocksBySector[sector] = [
      for (var block = first; block < trailerBlock; block++)
        if (block != 0) MctWriteBlock(block, Uint8List(16)),
      MctWriteBlock(
        trailerBlock,
        Uint8List.fromList(mfClassicFactoryTrailer),
        isTrailer: true,
      ),
    ];
  }
  return MctWritePlan(blocksBySector: blocksBySector);
}

/// Candidate keys for a write: the dump's own trailer keys first, then the
/// dictionary, without duplicates.
List<Uint8List> mctCandidateKeys(
  Iterable<Uint8List> dictionary, {
  CardSave? dump,
}) {
  final seen = <String>{};
  final keys = <Uint8List>[];
  void add(Uint8List key) {
    if (key.length == 6 && seen.add(bytesToHex(key))) keys.add(key);
  }

  if (dump != null) {
    final type = chameleonTagTypeGetMfClassicType(dump.tag);
    for (var sector = 0; sector < mfClassicGetSectorCount(type); sector++) {
      final block = mfClassicGetSectorTrailerBlockBySector(sector);
      if (block < dump.data.length && dump.data[block].length == 16) {
        add(dump.data[block].sublist(0, 6));
        add(dump.data[block].sublist(10, 16));
      }
    }
  }
  for (final key in gMifareClassicKeys) {
    add(key);
  }
  for (final key in dictionary) {
    add(key);
  }
  return keys;
}
