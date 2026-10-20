import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/mct_write.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';

Uint8List _block(int fill) => Uint8List.fromList(List.filled(16, fill));

// Key A FF.., AC FF078069, key B FF..
Uint8List get _trailer => Uint8List.fromList(mfClassicFactoryTrailer);

CardSave _card({
  List<Uint8List>? data,
  String uid = '11223344',
  TagType tag = TagType.mifare1K,
}) {
  final blocks =
      data ??
      [
        Uint8List.fromList(hexToBytes('11223344440804006263646566676869')),
        for (var b = 1; b < 64; b++)
          b % 4 == 3 ? _trailer : _block(b & 0xFF),
      ];
  return CardSave(
    id: 'test',
    uid: uid,
    sak: 0x08,
    name: 'test',
    tag: tag,
    data: blocks,
    color: Colors.blue,
    ats: Uint8List(0),
    atqa: Uint8List.fromList([0x00, 0x04]),
  );
}

void main() {
  test('factory trailer and access conditions are valid', () {
    expect(mfClassicFactoryTrailer, hasLength(16));
    expect(
      mfClassicAccessConditionsValid(mfClassicFactoryAccessConditions),
      isTrue,
    );
    expect(
      mfClassicAccessConditionsValid(Uint8List.fromList([0x00, 0x00, 0x00])),
      isFalse,
    );
  });

  test('manufacturer block needs a matching BCC for a 4-byte UID', () {
    final good = hexToBytes('11223344440804006263646566676869');
    expect(mfClassicManufacturerBlockValid(good, 4), isTrue);
    final bad = Uint8List.fromList(good)..[4] = 0x00;
    expect(mfClassicManufacturerBlockValid(bad, 4), isFalse);
    // A 7-byte UID has no BCC in byte 4.
    expect(mfClassicManufacturerBlockValid(bad, 7), isTrue);
  });

  test('dump plan skips block 0 and trailers by default', () {
    final plan = buildMctDumpWritePlan(
      _card(),
      MctWriteOptions(sectors: {for (var s = 0; s < 16; s++) s}),
    );
    final written = plan.blocksBySector.values
        .expand((b) => b)
        .map((b) => b.block)
        .toList();
    expect(written, isNot(contains(0)));
    expect(written, contains(1));
    // Trailers are written (writeTrailers defaults to true).
    expect(plan.blocksBySector[0]!.any((b) => b.isTrailer), isTrue);
  });

  test('manufacturer option includes block 0 only when BCC is valid', () {
    final plan = buildMctDumpWritePlan(
      _card(),
      MctWriteOptions(sectors: {0}, writeManufacturerBlock: true),
    );
    expect(plan.blocksBySector[0]!.any((b) => b.block == 0), isTrue);
    expect(plan.invalidManufacturerBlock, isFalse);

    final data = [for (final b in _card().data) Uint8List.fromList(b)];
    data[0][4] = 0x00; // break the BCC
    final broken = buildMctDumpWritePlan(
      _card(data: data),
      MctWriteOptions(sectors: {0}, writeManufacturerBlock: true),
    );
    expect(broken.invalidManufacturerBlock, isTrue);
    expect(broken.blocksBySector[0]?.any((b) => b.block == 0) ?? false, isFalse);
  });

  test('static access conditions replace trailer bytes 6-9', () {
    final plan = buildMctDumpWritePlan(
      _card(),
      MctWriteOptions(
        sectors: {1},
        staticAccessConditions: hexToBytes('78778869'),
      ),
    );
    final trailer = plan.blocksBySector[1]!.firstWhere((b) => b.isTrailer);
    expect(bytesToHex(trailer.data.sublist(6, 10)).toUpperCase(), '78778869');
  });

  test('a trailer with invalid access conditions is skipped', () {
    final data = [for (final b in _card().data) Uint8List.fromList(b)];
    data[7].setRange(6, 9, [0x00, 0x00, 0x00]); // sector 1 trailer
    final plan = buildMctDumpWritePlan(
      _card(data: data),
      MctWriteOptions(sectors: {1}),
    );
    expect(plan.invalidTrailerSectors, contains(1));
    expect(plan.blocksBySector[1]!.any((b) => b.isTrailer), isFalse);
  });

  test('factory format zeroes data blocks and restores trailers', () {
    final plan = buildFactoryFormatPlan([0, 1]);
    // Block 0 is never written.
    expect(
      plan.blocksBySector[0]!.any((b) => b.block == 0),
      isFalse,
    );
    final block1 = plan.blocksBySector[0]!.firstWhere((b) => b.block == 1);
    expect(block1.data, everyElement(0));
    final trailer = plan.blocksBySector[1]!.firstWhere((b) => b.isTrailer);
    expect(trailer.data, mfClassicFactoryTrailer);
  });

  test('single block write check enforces MCT rules', () {
    final good = hexToBytes('11223344440804006263646566676869');
    expect(
      mctCheckBlockWrite(0, good, allowManufacturerBlock: false, uidLength: 4),
      MctBlockRejection.manufacturerBlockLocked,
    );
    expect(
      mctCheckBlockWrite(0, good, allowManufacturerBlock: true, uidLength: 4),
      isNull,
    );
    expect(
      mctCheckBlockWrite(7, _block(0), allowManufacturerBlock: false,
          uidLength: 4),
      MctBlockRejection.invalidAccessConditions,
    );
    expect(
      mctCheckBlockWrite(1, _block(0xAA), allowManufacturerBlock: false,
          uidLength: 4),
      isNull,
    );
  });

  test('candidate keys start with the dump trailer keys then the dictionary',
      () {
    final data = [for (final b in _card().data) Uint8List.fromList(b)];
    data[3].setRange(0, 6, hexToBytes('A0A1A2A3A4A5')); // sector 0 key A
    final keys = mctCandidateKeys([
      hexToBytes('112233445566'),
    ], dump: _card(data: data));
    expect(bytesToHex(keys.first).toUpperCase(), 'A0A1A2A3A4A5');
    expect(keys.map((k) => bytesToHex(k).toUpperCase()),
        contains('112233445566'));
    // No duplicates.
    expect(keys.map((k) => bytesToHex(k)).toSet().length, keys.length);
  });

  test('sectors with data ignores fully unread sectors', () {
    final data = [for (final b in _card().data) Uint8List.fromList(b)];
    for (var b = 4; b < 8; b++) {
      data[b] = Uint8List(0); // sector 1 fully unread
    }
    expect(mctSectorsWithData(_card(data: data)), isNot(contains(1)));
    expect(mctSectorsWithData(_card(data: data)), contains(0));
  });
}
