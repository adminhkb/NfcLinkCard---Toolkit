import 'dart:convert';
import 'dart:typed_data';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';

CardSave pm3JsonToCardSave(String json) {
  Map<String, dynamic> data = jsonDecode(json);

  final String id = const Uuid().v4();
  final String uid = data['Card']['UID'] as String;
  String sakString = data['Card']['SAK'] as String;
  final int sak = hexToBytes(sakString)[0];
  String atqaString = data['Card']['ATQA'] as String;
  final List<int> atqa = [
    int.parse(atqaString.substring(2), radix: 16),
    int.parse(atqaString.substring(0, 2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];

  List<String> blocks = [];
  Map<String, dynamic> blockData = data['blocks'] as Map<String, dynamic>;
  for (int i = 0; blockData.containsKey(i.toString()); i++) {
    blocks.add(blockData[i.toString()] as String);
  }

  //Check if a block has more than 16 Bytes, Ultralight, return as unknown
  if (blocks[0].length > 32) {
    tag = TagType.unknown;
  } else {
    tag = mfClassicGetChameleonTagType(
        mfClassicGetCardTypeByBlockCount(blocks.length));
  }

  for (var block in blocks) {
    tagData.add(hexToBytes(block));
  }

  return CardSave(
      id: id,
      uid: uid,
      sak: sak,
      name: name,
      tag: tag,
      data: tagData,
      color: color,
      ats: Uint8List.fromList(ats),
      atqa: Uint8List.fromList(atqa));
}

CardSave flipperNfcToCardSave(String data) {
  final String id = const Uuid().v4();
  final String uid =
      RegExp(r'UID:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;
  final int sak = hexToBytes(
      RegExp(r'SAK:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!)[0];
  String atqaString =
      RegExp(r'ATQA:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;
  final List<int> atqa = [
    int.parse(atqaString.substring(0, 2), radix: 16),
    int.parse(atqaString.substring(2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];
  List<String> blocks = [];
  for (var block in data.split("\n")) {
    if (block.startsWith("Block")) {
      blocks.add(block.split(":")[1].trim().replaceAll('?', '0'));
    }
  }

  //Check if a block has more than 16 Bytes, Ultralight, return as unknown
  if (blocks[0].replaceAll(' ', '').length > 32) {
    tag = TagType.unknown;
  } else {
    tag = mfClassicGetChameleonTagType(
        mfClassicGetCardTypeByBlockCount(blocks.length));
  }

  for (var block in blocks) {
    tagData.add(hexToBytes(block));
  }

  return CardSave(
      id: id,
      uid: uid,
      sak: sak,
      name: name,
      tag: tag,
      data: tagData,
      color: color,
      ats: Uint8List.fromList(ats),
      atqa: Uint8List.fromList(atqa));
}

final _mctSectorHeader = RegExp(r'^\+Sector:\s*(\d+)\s*$');
final _mctBlockLine = RegExp(r'^[0-9A-Fa-f-]{32}$');
const _mctNoDataBlock = '--------------------------------';

/// True when [data] looks like a MIFARE Classic Tool text dump.
bool isMctDump(String data) =>
    RegExp(r'^\s*\+Sector:\s*\d+\s*$', multiLine: true).hasMatch(data);

/// A MIFARE Classic Tool dump converted to a [CardSave], with what could not
/// be carried over exactly.
class MctImportResult {
  final CardSave card;

  /// Sectors present in the file, in file order.
  final List<int> sectors;

  /// Blocks stored as unread: missing sectors, `*` sectors and `----` lines.
  final int unreadBlocks;

  /// Blocks where MCT marked only some bytes as unknown (usually a key in a
  /// sector trailer). The unknown nibbles are stored as 0.
  final int partialBlocks;

  const MctImportResult({
    required this.card,
    required this.sectors,
    required this.unreadBlocks,
    required this.partialBlocks,
  });
}

/// Parses an MCT dump. Blocks are placed by their `+Sector:` header, so
/// sectors MCT skipped stay unread instead of shifting later blocks.
MctImportResult parseMctDump(String data) {
  final blocksBySector = <int, List<String>>{};
  int? sector;

  for (final rawLine in data.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final header = _mctSectorHeader.firstMatch(line);
    if (header != null) {
      sector = int.parse(header.group(1)!);
      if (sector > 39) {
        throw FormatException('MCT sector $sector is out of range');
      }
      if (blocksBySector.containsKey(sector)) {
        throw FormatException('MCT sector $sector appears twice');
      }
      blocksBySector[sector] = [];
      continue;
    }
    if (sector == null) {
      throw const FormatException('MCT data found before the first sector');
    }
    if (line.startsWith('*')) {
      // MCT writes "*No keys found or dead sector*" for unread sectors;
      // their blocks stay unread.
      continue;
    }
    if (!_mctBlockLine.hasMatch(line)) {
      throw FormatException('Invalid MCT block in sector $sector');
    }
    final blocks = blocksBySector[sector]!;
    if (blocks.length >= mfClassicGetBlockCountBySector(sector)) {
      throw FormatException('Too many blocks in MCT sector $sector');
    }
    blocks.add(line);
  }

  if (blocksBySector.isEmpty) {
    throw const FormatException('MCT dump has no sector');
  }
  final manufacturer = blocksBySector[0];
  if (manufacturer == null ||
      manufacturer.isEmpty ||
      !RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(manufacturer.first)) {
    throw const FormatException('MCT dump has no readable manufacturer block');
  }

  final block0 = hexToBytes(manufacturer.first);
  final maxSector = blocksBySector.keys.reduce((a, b) => a > b ? a : b);
  final MifareClassicType type;
  if (maxSector > 31) {
    type = MifareClassicType.m4k;
  } else if (maxSector > 17) {
    type = MifareClassicType.m2k;
  } else if (maxSector <= 4 && block0[5] == 0x09) {
    type = MifareClassicType.mini;
  } else {
    type = MifareClassicType.m1k;
  }
  final blockCount = switch (type) {
    MifareClassicType.m4k => 256,
    MifareClassicType.m2k => 128,
    MifareClassicType.mini => 20,
    _ => maxSector > 15 ? 72 : 64,
  };

  final tagData = List<Uint8List>.generate(blockCount, (_) => Uint8List(0));
  var partialBlocks = 0;
  for (final entry in blocksBySector.entries) {
    final first = mfClassicGetFirstBlockCountBySector(entry.key);
    for (var offset = 0; offset < entry.value.length; offset++) {
      final line = entry.value[offset];
      if (line == _mctNoDataBlock) continue;
      if (line.contains('-')) partialBlocks++;
      tagData[first + offset] = hexToBytes(line.replaceAll('-', '0'));
    }
  }
  final unreadBlocks = tagData.where((block) => block.isEmpty).length;

  // A 4-byte UID is followed by its BCC; otherwise block 0 holds a 7-byte UID.
  final hasUid4 = block0[4] == calculateBcc(block0.sublist(0, 4));
  final uid = bytesToHex(block0.sublist(0, hasUid4 ? 4 : 7)).toUpperCase();
  final sak = hasUid4 ? block0[5] : block0[7];
  final atqa = hasUid4 ? [block0[7], block0[6]] : [block0[9], block0[8]];

  return MctImportResult(
    card: CardSave(
        id: const Uuid().v4(),
        uid: uid,
        sak: sak,
        name: uid,
        tag: mfClassicGetChameleonTagType(type),
        data: tagData,
        color: Colors.deepOrange,
        ats: Uint8List(0),
        atqa: Uint8List.fromList(atqa)),
    sectors: blocksBySector.keys.toList(),
    unreadBlocks: unreadBlocks,
    partialBlocks: partialBlocks,
  );
}

CardSave mctToCardSave(String data) => parseMctDump(data).card;

/// Exports a four-byte-UID MIFARE Classic dump using MCT sector headers.
/// Unread blocks keep MCT's no-data marker instead of becoming zeroed data.
String cardSaveToMct(CardSave card) {
  if (!isMifareClassic(card.tag)) {
    throw const FormatException('Only MIFARE Classic dumps can be exported');
  }
  final uid = card.uid.replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(uid) ||
      card.data.isEmpty ||
      card.data.first.length != 16) {
    throw const FormatException('MCT export needs a readable 4-byte UID block');
  }

  final type = chameleonTagTypeGetMfClassicType(card.tag);
  final isEV1 = chameleonTagSaveCheckForMifareClassicEV1(card);
  final sectorCount = mfClassicGetSectorCount(type, isEV1: isEV1);
  final lines = <String>[];
  for (var sector = 0; sector < sectorCount; sector++) {
    lines.add('+Sector: $sector');
    final firstBlock = mfClassicGetFirstBlockCountBySector(sector);
    final blockCount = mfClassicGetBlockCountBySector(sector);
    for (var offset = 0; offset < blockCount; offset++) {
      final index = firstBlock + offset;
      final block = index < card.data.length ? card.data[index] : Uint8List(0);
      if (block.length == 16) {
        lines.add(bytesToHex(block).toUpperCase());
      } else if (block.isEmpty) {
        lines.add('--------------------------------');
      } else {
        throw FormatException('Invalid MIFARE Classic block $index');
      }
    }
  }
  return lines.join('\n');
}

CardSave flipperRfidToCardSave(String data) {
  final String id = const Uuid().v4();
  final String type = RegExp(r'Key type:\s+(.*)').firstMatch(data)!.group(1)!;
  const Color color = Colors.deepOrange;

  final TagType tag;
  String uid = RegExp(r'Data:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;

  switch (type) {
    case 'EM4100':
      tag = TagType.em410X64;
      break;
    case 'EM4100/32':
      tag = TagType.em410X32;
      break;
    case 'EM4100/16':
      tag = TagType.em410X16;
      break;
    case 'H10301':
      tag = TagType.hidProx;
      uid = HIDCard(
              hidType: 1,
              facilityCode: hexToBytes(uid)[0],
              uid: Uint8List.fromList(
                  [0, 0, 0, ...hexToBytes(uid).sublist(1, 3)]),
              issueLevel: 0,
              oem: 0)
          .toString();
      break;
    default:
      tag = TagType.unknown;
  }

  return CardSave(id: id, uid: uid, name: uid, tag: tag, color: color);
}
