import 'package:flutter_test/flutter_test.dart';
import 'package:nlc_toolkit/helpers/card_save_converters.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';

// UID 11223344, BCC 44, SAK 08, ATQA 0004.
const _block0 = '11223344440804006263646566676869';
const _trailer = 'FFFFFFFFFFFFFF078069FFFFFFFFFFFF';
const _empty = '00000000000000000000000000000000';

String _sector(int sector, {String? data, int blocks = 4}) {
  final fill = data ?? _empty;
  return [
    '+Sector: $sector',
    for (var i = 0; i < blocks - 1; i++)
      sector == 0 && i == 0 ? _block0 : fill,
    _trailer,
  ].join('\n');
}

void main() {
  test('detects MCT dumps by any sector header', () {
    expect(isMctDump(_sector(0)), isTrue);
    expect(isMctDump('\n+Sector: 2\n$_empty'), isTrue);
    expect(isMctDump('Filetype: Flipper NFC device'), isFalse);
  });

  test('imports a complete 1K dump and exports it back unchanged', () {
    final dump = [for (var s = 0; s < 16; s++) _sector(s)].join('\n');
    final result = parseMctDump(dump);
    final card = result.card;

    expect(card.tag, TagType.mifare1K);
    expect(card.data, hasLength(64));
    expect(card.uid, '11223344');
    expect(card.sak, 0x08);
    expect(card.atqa, [0x00, 0x04]);
    expect(result.sectors, hasLength(16));
    expect(result.unreadBlocks, 0);
    expect(result.partialBlocks, 0);
    expect(cardSaveToMct(card), dump);
  });

  test('keeps blocks in place when MCT skipped a sector', () {
    const sector3 = '03030303030303030303030303030303';
    final dump = [
      _sector(0),
      _sector(1),
      _sector(3, data: sector3),
    ].join('\n');
    final result = parseMctDump(dump);

    expect(result.card.data[8], isEmpty);
    expect(result.card.data[11], isEmpty);
    expect(result.card.data[12].first, 0x03);
    expect(result.unreadBlocks, 64 - 12);
  });

  test('treats a starred sector and dashed lines as unread', () {
    final dump = [
      _sector(0),
      '+Sector: 1',
      '*No keys found or dead sector*',
      '+Sector: 2',
      '--------------------------------',
      _empty,
      _empty,
      _trailer,
    ].join('\r\n');
    final card = parseMctDump(dump).card;

    expect(card.data.sublist(4, 8).every((block) => block.isEmpty), isTrue);
    expect(card.data[8], isEmpty);
    expect(card.data[9], hasLength(16));
  });

  test('stores unknown key bytes as zero and counts them', () {
    final dump = [
      _sector(0),
      '+Sector: 1',
      _empty,
      _empty,
      _empty,
      '------------FF078069FFFFFFFFFFFF',
    ].join('\n');
    final result = parseMctDump(dump);

    expect(result.partialBlocks, 1);
    expect(result.card.data[7].sublist(0, 6), everyElement(0));
    expect(result.card.data[7][6], 0xFF);
  });

  test('reads a 7-byte UID from the manufacturer block', () {
    final dump = _sector(0).replaceFirst(
      _block0,
      '04A1B2C355E5F6084400000000000000',
    );
    final card = parseMctDump(dump).card;

    expect(card.uid, '04A1B2C355E5F6');
    expect(card.sak, 0x08);
    expect(card.atqa, [0x00, 0x44]);
  });

  test('places 16-block 4K sectors correctly', () {
    const sector32 = '32323232323232323232323232323232';
    final dump = [_sector(0), _sector(32, data: sector32, blocks: 16)]
        .join('\n');
    final card = parseMctDump(dump).card;

    expect(card.tag, TagType.mifare4K);
    expect(card.data, hasLength(256));
    expect(card.data[128].first, 0x32);
    expect(card.data[143], hasLength(16));
    expect(card.data[144], isEmpty);
  });

  test('rejects malformed dumps', () {
    expect(() => parseMctDump(_empty), throwsFormatException);
    expect(() => parseMctDump(_sector(1)), throwsFormatException);
    expect(() => parseMctDump('${_sector(0)}\n$_empty'), throwsFormatException);
    expect(
      () => parseMctDump('${_sector(0)}\n${_sector(0)}'),
      throwsFormatException,
    );
    expect(
      () => parseMctDump(_sector(0).replaceFirst(_trailer, 'XYZ')),
      throwsFormatException,
    );
    expect(() => parseMctDump('+Sector: 40\n$_empty'), throwsFormatException);
  });
}
