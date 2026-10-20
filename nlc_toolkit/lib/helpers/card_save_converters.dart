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

CardSave mctToCardSave(String data) {
  final String id = const Uuid().v4();
  final List<String> blocks = data
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('+Sector:'))
      .toList();
  if (blocks.isEmpty ||
      !RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(blocks.first)) {
    throw const FormatException('MCT dump has no readable manufacturer block');
  }
  final String uid = blocks.first.substring(0, 8);
  final int sak = hexToBytes(blocks.first.substring(10, 12))[0];
  String atqaString = blocks.first.substring(12, 16);
  final List<int> atqa = [
    int.parse(atqaString.substring(2), radix: 16),
    int.parse(atqaString.substring(0, 2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];
  tag = mfClassicGetChameleonTagType(
      mfClassicGetCardTypeByBlockCount(blocks.length));

  for (var block in blocks) {
    if (block == '--------------------------------') {
      tagData.add(Uint8List(0));
    } else if (RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(block)) {
      tagData.add(hexToBytes(block));
    } else {
      throw const FormatException('Invalid MCT block');
    }
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
