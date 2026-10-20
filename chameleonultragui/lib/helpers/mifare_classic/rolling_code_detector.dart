import 'dart:typed_data';

/// A sequence can show changing data without proving the access system's
/// protocol or a rolling-code mechanism.
enum RollingCodeSequenceVerdict {
  insufficient,
  noChangeObserved,
  dataChanged,
  repeatedChange,
  rollingCompatible,
}

/// Confidence in the observed comparison, never in a particular protocol.
enum RollingCodeConfidenceLevel { low, medium, high }

/// Values decoded from a valid MIFARE Classic value block in all three scans.
/// The values are signed 32-bit little-endian integers. An address change is
/// recorded separately and does not establish a counter or rolling code.
class RollingCodeValueChange {
  final int blockIndex;
  final int beforeValue;
  final int afterFirstUseValue;
  final int afterSecondUseValue;
  final int beforeAddress;
  final int afterFirstUseAddress;
  final int afterSecondUseAddress;

  const RollingCodeValueChange({
    required this.blockIndex,
    required this.beforeValue,
    required this.afterFirstUseValue,
    required this.afterSecondUseValue,
    required this.beforeAddress,
    required this.afterFirstUseAddress,
    required this.afterSecondUseAddress,
  });

  Map<String, Object?> toJson() => {
    'blockIndex': blockIndex,
    'beforeValue': beforeValue,
    'afterFirstUseValue': afterFirstUseValue,
    'afterSecondUseValue': afterSecondUseValue,
    'beforeAddress': beforeAddress,
    'afterFirstUseAddress': afterFirstUseAddress,
    'afterSecondUseAddress': afterSecondUseAddress,
  };
}

class RollingCodeSequenceResult {
  final RollingCodeSequenceVerdict verdict;

  /// Intentionally always null: dumps cannot prove the mechanism used by a
  /// physical access reader, including when changes follow two known uses.
  final bool? hasRollingCode;

  /// Null means the captures cannot establish a change or its absence.
  final bool? dynamicDataObserved;
  final RollingCodeConfidenceLevel confidenceLevel;
  final List<int> firstChangedBlocks;
  final List<int> secondChangedBlocks;
  final List<int> repeatedChangedBlocks;

  /// A block is treated as a value block if any of the three captures has a
  /// valid MIFARE value-block encoding. It is excluded from rollingCompatible.
  final List<int> valueChangedBlocks;
  final List<RollingCodeValueChange> valueChanges;

  /// Physical data blocks omitted because a primary capture is absent, has
  /// an invalid size, or contains all zeroes (which may be a failed read).
  final List<int> ignoredBlocks;

  /// Control scan changes observed before any confirmed use.
  final List<int> unstableControlBlocks;

  /// An idle control was provided, but these blocks could not be verified.
  final List<int> unverifiableControlBlocks;

  /// Byte positions (0..15) changed in each chronological transition.
  final Map<int, List<int>> firstChangedBytesByBlock;
  final Map<int, List<int>> secondChangedBytesByBlock;
  final Map<int, List<int>> repeatedChangedBytesByBlock;

  /// Repeated non-value byte changes that also passed the optional idle check.
  final Map<int, List<int>> rollingCompatibleBytesByBlock;

  final int comparedBlockCount;
  final String details;

  const RollingCodeSequenceResult({
    required this.verdict,
    required this.hasRollingCode,
    required this.dynamicDataObserved,
    required this.confidenceLevel,
    required this.firstChangedBlocks,
    required this.secondChangedBlocks,
    required this.repeatedChangedBlocks,
    required this.valueChangedBlocks,
    required this.valueChanges,
    required this.ignoredBlocks,
    required this.unstableControlBlocks,
    required this.unverifiableControlBlocks,
    required this.firstChangedBytesByBlock,
    required this.secondChangedBytesByBlock,
    required this.repeatedChangedBytesByBlock,
    required this.rollingCompatibleBytesByBlock,
    required this.comparedBlockCount,
    required this.details,
  });

  Map<String, Object?> toJson() => {
    'verdict': verdict.name,
    'hasRollingCode': hasRollingCode,
    'dynamicDataObserved': dynamicDataObserved,
    'confidenceLevel': confidenceLevel.name.toUpperCase(),
    'firstChangedBlocks': firstChangedBlocks,
    'secondChangedBlocks': secondChangedBlocks,
    'repeatedChangedBlocks': repeatedChangedBlocks,
    'valueChangedBlocks': valueChangedBlocks,
    'valueChanges': valueChanges.map((item) => item.toJson()).toList(),
    'ignoredBlocks': ignoredBlocks,
    'unstableControlBlocks': unstableControlBlocks,
    'unverifiableControlBlocks': unverifiableControlBlocks,
    'firstChangedBytesByBlock': _byteMapToJson(firstChangedBytesByBlock),
    'secondChangedBytesByBlock': _byteMapToJson(secondChangedBytesByBlock),
    'repeatedChangedBytesByBlock': _byteMapToJson(repeatedChangedBytesByBlock),
    'rollingCompatibleBytesByBlock':
        _byteMapToJson(rollingCompatibleBytesByBlock),
    'comparedBlockCount': comparedBlockCount,
    'details': details,
  };

  static Map<String, List<int>> _byteMapToJson(Map<int, List<int>> source) => {
    for (final entry in source.entries) '${entry.key}': entry.value,
  };
}

/// Compares three independent, chronological MIFARE Classic 1K/4K captures.
///
/// [idleControl], when present, was captured after [before] without using the
/// badge. It is used to reject changes that also occur without a reader pass.
/// [usesConfirmed] means an actual reader use occurred before each of the two
/// later captures. The caller must establish this externally; the dumps cannot.
/// Extra EV1 signature blocks beyond [physicalBlockCount] are ignored.
class RollingCodeDetector {
  static RollingCodeSequenceResult analyze({
    required List<Uint8List> before,
    required List<Uint8List> afterFirstUse,
    required List<Uint8List> afterSecondUse,
    List<Uint8List>? idleControl,
    required int physicalBlockCount,
    required bool usesConfirmed,
  }) {
    if (physicalBlockCount != 64 && physicalBlockCount != 256) {
      throw ArgumentError.value(
        physicalBlockCount,
        'physicalBlockCount',
        'Only MIFARE Classic 1K (64) and 4K (256) are supported',
      );
    }

    final captures = <List<Uint8List>>[
      before,
      afterFirstUse,
      afterSecondUse,
      if (idleControl != null) idleControl,
    ];
    if (captures.any((capture) => capture.length < physicalBlockCount)) {
      return _insufficient('A capture has fewer than the expected physical '
          '$physicalBlockCount blocks.');
    }
    for (var i = 0; i < captures.length; i++) {
      for (var j = i + 1; j < captures.length; j++) {
        if (identical(captures[i], captures[j])) {
          return _insufficient('The scans must be independent captures.');
        }
      }
    }

    final manufacturer = _readableBlock(before, 0);
    if (manufacturer == null) {
      return _insufficient('The manufacturer/UID block is unreadable.');
    }
    for (final capture in captures.skip(1)) {
      final candidate = _readableBlock(capture, 0);
      if (candidate == null || !_sameBytes(manufacturer, candidate)) {
        return _insufficient(
          'Manufacturer/UID blocks differ or are unreadable; the scans '
          'cannot be attributed to the same card.',
        );
      }
    }

    final firstBytes = <int, List<int>>{};
    final secondBytes = <int, List<int>>{};
    final repeatedBytes = <int, List<int>>{};
    final compatibleBytes = <int, List<int>>{};
    final valueChanged = <int>[];
    final valueChanges = <RollingCodeValueChange>[];
    final ignored = <int>[];
    final unstableControl = <int>[];
    final unverifiableControl = <int>[];
    var compared = 0;

    for (var index = 1; index < physicalBlockCount; index++) {
      if (_isTrailer(index)) continue;

      final first = _readableBlock(before, index);
      final second = _readableBlock(afterFirstUse, index);
      final third = _readableBlock(afterSecondUse, index);
      if (first == null || second == null || third == null) {
        ignored.add(index);
        continue;
      }
      compared++;

      final firstDelta = _changedBytePositions(first, second);
      final secondDelta = _changedBytePositions(second, third);
      if (firstDelta.isNotEmpty) firstBytes[index] = firstDelta;
      if (secondDelta.isNotEmpty) secondBytes[index] = secondDelta;
      final repeated = firstDelta.toSet().intersection(secondDelta.toSet()).toList()
        ..sort();
      if (repeated.isNotEmpty) repeatedBytes[index] = repeated;

      final beforeValue = _parseValueBlock(first);
      final afterFirstValue = _parseValueBlock(second);
      final afterSecondValue = _parseValueBlock(third);
      final valueLike = beforeValue != null ||
          afterFirstValue != null ||
          afterSecondValue != null;
      if (valueLike && (firstDelta.isNotEmpty || secondDelta.isNotEmpty)) {
        valueChanged.add(index);
      }
      if (beforeValue != null &&
          afterFirstValue != null &&
          afterSecondValue != null &&
          (firstDelta.isNotEmpty || secondDelta.isNotEmpty)) {
        valueChanges.add(RollingCodeValueChange(
          blockIndex: index,
          beforeValue: beforeValue.value,
          afterFirstUseValue: afterFirstValue.value,
          afterSecondUseValue: afterSecondValue.value,
          beforeAddress: beforeValue.address,
          afterFirstUseAddress: afterFirstValue.address,
          afterSecondUseAddress: afterSecondValue.address,
        ));
      }

      List<int>? idleDelta;
      if (idleControl != null) {
        final idle = _readableBlock(idleControl, index);
        if (idle == null) {
          unverifiableControl.add(index);
        } else {
          idleDelta = _changedBytePositions(first, idle);
          if (idleDelta.isNotEmpty) unstableControl.add(index);
        }
      }

      if (repeated.isEmpty || valueLike || !usesConfirmed) continue;
      if (idleControl == null) {
        compatibleBytes[index] = repeated;
      } else if (idleDelta != null) {
        final idleChanged = idleDelta.toSet();
        final stableRepeated = repeated
            .where((position) => !idleChanged.contains(position))
            .toList();
        if (stableRepeated.isNotEmpty) compatibleBytes[index] = stableRepeated;
      }
    }

    final firstBlocks = firstBytes.keys.toList(growable: false);
    final secondBlocks = secondBytes.keys.toList(growable: false);
    final secondSet = secondBytes.keys.toSet();
    final repeatedBlocks = firstBlocks
        .where((index) => secondSet.contains(index))
        .toList(growable: false);
    final anyChanged = firstBlocks.isNotEmpty || secondBlocks.isNotEmpty;

    final RollingCodeSequenceVerdict verdict;
    final RollingCodeConfidenceLevel confidence;
    final bool? dynamicDataObserved;
    final String details;
    if (compatibleBytes.isNotEmpty) {
      verdict = RollingCodeSequenceVerdict.rollingCompatible;
      confidence = idleControl == null
          ? RollingCodeConfidenceLevel.medium
          : RollingCodeConfidenceLevel.high;
      dynamicDataObserved = true;
      final idleDetail = idleControl == null
          ? ''
          : ' and stayed stable in the idle control';
      details = 'The same non-value byte changed after each of two reported '
          'reader uses$idleDetail. This is compatible with evolving data, but '
          'does not identify or prove a rolling-code protocol.';
    } else if (repeatedBlocks.isNotEmpty) {
      verdict = RollingCodeSequenceVerdict.repeatedChange;
      confidence = RollingCodeConfidenceLevel.medium;
      dynamicDataObserved = true;
      details = 'One or more data blocks changed in both transitions. '
          'A value block, different byte positions, an unconfirmed reader '
          'use, or the idle control prevents a stronger conclusion.';
    } else if (anyChanged) {
      verdict = RollingCodeSequenceVerdict.dataChanged;
      confidence = RollingCodeConfidenceLevel.medium;
      dynamicDataObserved = true;
      details = 'Readable data changed in at least one transition. The '
          'cause and any rolling-code mechanism remain unknown.';
    } else if (unstableControl.isNotEmpty) {
      verdict = RollingCodeSequenceVerdict.dataChanged;
      confidence = RollingCodeConfidenceLevel.low;
      dynamicDataObserved = true;
      details = 'Data changed during the control scan without a confirmed '
          'reader use. No change was observed in the two main transitions; '
          'the cause of the control change is unknown.';
    } else if (ignored.isNotEmpty ||
        unverifiableControl.isNotEmpty ||
        compared == 0) {
      verdict = RollingCodeSequenceVerdict.insufficient;
      confidence = RollingCodeConfidenceLevel.low;
      dynamicDataObserved = null;
      details = 'No change was observed in the comparable data, but missing, '
          'invalid, or all-zero blocks prevent a complete comparison, '
          'including the optional idle control when supplied.';
    } else {
      verdict = RollingCodeSequenceVerdict.noChangeObserved;
      confidence = RollingCodeConfidenceLevel.medium;
      dynamicDataObserved = false;
      details = 'All readable physical data blocks were unchanged across '
          'these captures. This does not rule out later changes.';
    }

    return RollingCodeSequenceResult(
      verdict: verdict,
      hasRollingCode: null,
      dynamicDataObserved: dynamicDataObserved,
      confidenceLevel: confidence,
      firstChangedBlocks: List.unmodifiable(firstBlocks),
      secondChangedBlocks: List.unmodifiable(secondBlocks),
      repeatedChangedBlocks: List.unmodifiable(repeatedBlocks),
      valueChangedBlocks: List.unmodifiable(valueChanged),
      valueChanges: List.unmodifiable(valueChanges),
      ignoredBlocks: List.unmodifiable(ignored),
      unstableControlBlocks: List.unmodifiable(unstableControl),
      unverifiableControlBlocks: List.unmodifiable(unverifiableControl),
      firstChangedBytesByBlock: _immutableByteMap(firstBytes),
      secondChangedBytesByBlock: _immutableByteMap(secondBytes),
      repeatedChangedBytesByBlock: _immutableByteMap(repeatedBytes),
      rollingCompatibleBytesByBlock: _immutableByteMap(compatibleBytes),
      comparedBlockCount: compared,
      details: details,
    );
  }

  static RollingCodeSequenceResult _insufficient(String details) =>
      RollingCodeSequenceResult(
        verdict: RollingCodeSequenceVerdict.insufficient,
        hasRollingCode: null,
        dynamicDataObserved: null,
        confidenceLevel: RollingCodeConfidenceLevel.low,
        firstChangedBlocks: const [],
        secondChangedBlocks: const [],
        repeatedChangedBlocks: const [],
        valueChangedBlocks: const [],
        valueChanges: const [],
        ignoredBlocks: const [],
        unstableControlBlocks: const [],
        unverifiableControlBlocks: const [],
        firstChangedBytesByBlock: const {},
        secondChangedBytesByBlock: const {},
        repeatedChangedBytesByBlock: const {},
        rollingCompatibleBytesByBlock: const {},
        comparedBlockCount: 0,
        details: details,
      );

  static Map<int, List<int>> _immutableByteMap(Map<int, List<int>> source) =>
      Map.unmodifiable({
        for (final entry in source.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      });

  static bool _isTrailer(int block) =>
      block < 128 ? block % 4 == 3 : (block - 128) % 16 == 15;

  static Uint8List? _readableBlock(List<Uint8List> dump, int index) {
    if (index >= dump.length) return null;
    final block = dump[index];
    if (block.length != 16 || block.every((byte) => byte == 0)) return null;
    return block;
  }

  static bool _sameBytes(Uint8List first, Uint8List second) {
    for (var index = 0; index < 16; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  static List<int> _changedBytePositions(Uint8List first, Uint8List second) => [
    for (var index = 0; index < 16; index++)
      if (first[index] != second[index]) index,
  ];

  static _ValueBlock? _parseValueBlock(Uint8List block) {
    for (var index = 0; index < 4; index++) {
      if (block[index] != block[index + 8] ||
          block[index + 4] != (block[index] ^ 0xFF)) {
        return null;
      }
    }
    if (block[12] != block[14] ||
        block[13] != block[15] ||
        block[12] != (block[13] ^ 0xFF)) {
      return null;
    }
    final raw = block[0] |
        (block[1] << 8) |
        (block[2] << 16) |
        (block[3] << 24);
    return _ValueBlock(raw.toSigned(32), block[12]);
  }
}

class _ValueBlock {
  final int value;
  final int address;

  const _ValueBlock(this.value, this.address);
}
