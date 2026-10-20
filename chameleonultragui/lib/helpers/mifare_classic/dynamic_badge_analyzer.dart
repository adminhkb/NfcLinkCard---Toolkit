import 'dart:typed_data';

/// Confidence in the evidence reported by the analyzer, not in a particular
/// manufacturer's use of rolling codes.
enum DynamicBadgeConfidenceLevel { low, medium, high }

/// A warning level for a static copy of the observed data. `none` means that
/// this analyzer found no specific warning, not that copying is safe.
enum DynamicBadgeRiskLevel { none, low, critical }

class DynamicBadgeEvidence {
  final String code;
  final List<int> blockIndices;
  final String description;

  const DynamicBadgeEvidence({
    required this.code,
    required this.blockIndices,
    required this.description,
  });

  Map<String, Object?> toJson() => {
    'code': code,
    'blockIndices': blockIndices,
    'description': description,
  };
}

class DynamicBadgeAnalysis {
  final String systemDetected;

  /// A HEXACT-style Key A and an INTRATONE ASCII marker were both observed.
  /// This identifies a static fingerprint, not a confirmed write mode.
  final bool combinedHexactIntratoneFingerprint;

  /// Null means that neither the presence nor absence of a rolling-code
  /// mechanism has been established. A static signature or a changed data
  /// block alone cannot prove what mechanism an access system uses.
  final bool? hasRollingCode;

  /// True when a data block changed across comparable captures; false only
  /// when all physical data blocks were comparable and identical; otherwise
  /// null. This is intentionally separate from [hasRollingCode].
  final bool? dynamicDataObserved;
  final DynamicBadgeConfidenceLevel confidenceLevel;
  final DynamicBadgeRiskLevel riskLevel;
  final String details;
  final List<DynamicBadgeEvidence> evidence;

  const DynamicBadgeAnalysis({
    required this.systemDetected,
    required this.combinedHexactIntratoneFingerprint,
    required this.hasRollingCode,
    required this.dynamicDataObserved,
    required this.confidenceLevel,
    required this.riskLevel,
    required this.details,
    required this.evidence,
  });

  Map<String, Object?> toJson() => {
    'systemDetected': systemDetected,
    'combinedHexactIntratoneFingerprint': combinedHexactIntratoneFingerprint,
    'hasRollingCode': hasRollingCode,
    'dynamicDataObserved': dynamicDataObserved,
    'confidenceLevel': confidenceLevel.name.toUpperCase(),
    'riskLevel': riskLevel.name.toUpperCase(),
    'details': details,
    'evidence': evidence.map((item) => item.toJson()).toList(),
  };
}

/// Examines physical MIFARE Classic 1K or 4K blocks without accessing a card.
///
/// [blocks] and [previousBlocks] must be independently captured dumps of the
/// same card for a differential conclusion. The manufacturer/UID block must
/// match. Pass `physicalBlockCount: 256` for a 4K card; the 1K default is 64.
/// EV1 signature blocks beyond physical block 63 are intentionally ignored.
/// Empty or all-zero blocks can represent failed reads in NLC Toolkit, so they
/// cannot establish either a change or the absence of change.
class DynamicBadgeAnalyzer {
  static DynamicBadgeAnalysis analyze(
    List<Uint8List> blocks, {
    List<Uint8List>? previousBlocks,
    int physicalBlockCount = 64,
  }) {
    if (physicalBlockCount != 64 && physicalBlockCount != 256) {
      throw ArgumentError.value(
        physicalBlockCount,
        'physicalBlockCount',
        'Only MIFARE Classic 1K (64) and 4K (256) are supported',
      );
    }

    final evidence = <DynamicBadgeEvidence>[];
    final sectorCount = physicalBlockCount == 64 ? 16 : 40;
    final hexactKeyBlocks = <int>[];
    final installerKeyBlocks = <int>[];
    final valueBlocks = <int>[];
    final asciiMarkerBlocks = <int>[];
    final asciiMarkers = <String>{};

    for (var sector = 0; sector < sectorCount; sector++) {
      final trailerIndex = _trailerBlock(sector);
      final trailer = _validBlock(blocks, trailerIndex, physicalBlockCount);
      if (trailer == null) continue;
      if (_matchesKeyA(trailer, const [0x48, 0x45, 0x58, 0x41, 0x43, 0x54])) {
        hexactKeyBlocks.add(trailerIndex);
      }
      if (_matchesKeyA(trailer, const [0x88, 0x29, 0xDA, 0x9D, 0xAF, 0x76])) {
        installerKeyBlocks.add(trailerIndex);
      }
    }

    for (var index = 60; index <= 62; index++) {
      final block = _validBlock(blocks, index, physicalBlockCount);
      if (block == null) continue;
      final ascii = String.fromCharCodes(block).toUpperCase();
      var found = false;
      for (final marker in const ['HEXACT', 'COGELEC', 'INTRATONE']) {
        if (ascii.contains(marker)) {
          asciiMarkers.add(marker);
          found = true;
        }
      }
      if (found) asciiMarkerBlocks.add(index);
    }

    for (var index = 1; index < physicalBlockCount; index++) {
      if (_isTrailer(index)) continue;
      final block = _validBlock(blocks, index, physicalBlockCount);
      if (block != null && _isValueBlock(block)) valueBlocks.add(index);
    }

    if (hexactKeyBlocks.isNotEmpty) {
      evidence.add(
        DynamicBadgeEvidence(
          code: 'hexact_key',
          blockIndices: hexactKeyBlocks,
          description:
              'A known HEXACT-style Key A appears in sector trailers. '
              'A key alone does not identify the operator or a rolling code.',
        ),
      );
    }
    if (asciiMarkerBlocks.isNotEmpty) {
      evidence.add(
        DynamicBadgeEvidence(
          code: 'ascii_marker',
          blockIndices: asciiMarkerBlocks,
          description:
              'ASCII marker(s) found: ${asciiMarkers.join(', ')}. '
              'A printed name does not establish the access protocol.',
        ),
      );
    }

    final recurrentInstallerKey = installerKeyBlocks.length > sectorCount / 2;
    if (recurrentInstallerKey) {
      evidence.add(
        DynamicBadgeEvidence(
          code: 'installer_key_pattern',
          blockIndices: installerKeyBlocks,
          description:
              'The same installer-style Key A appears in '
              '${installerKeyBlocks.length} of $sectorCount sectors. '
              'This is an indicative pattern, not a manufacturer identification.',
        ),
      );
    }

    final upperDataBlocks = <int>[];
    var allUpperDataZero = true;
    for (var sector = 3; sector <= 15; sector++) {
      for (var offset = 0; offset < 3; offset++) {
        final index = sector * 4 + offset;
        final block = _validBlock(blocks, index, physicalBlockCount);
        if (block == null || !_isZero(block)) {
          allUpperDataZero = false;
        } else {
          upperDataBlocks.add(index);
        }
      }
    }
    if (allUpperDataZero) {
      evidence.add(
        DynamicBadgeEvidence(
          code: 'zero_upper_data',
          blockIndices: upperDataBlocks,
          description:
              'Data blocks in sectors 3–15 contain zeroes. '
              'NLC Toolkit can also use zeroes for failed reads, so empty '
              'sectors are not established.',
        ),
      );
    }

    if (valueBlocks.isNotEmpty) {
      evidence.add(
        DynamicBadgeEvidence(
          code: 'value_block',
          blockIndices: valueBlocks,
          description:
              'Valid MIFARE Classic value-block structure found. '
              'It may hold a static value and does not prove a counter or '
              'rolling code.',
        ),
      );
    }

    final comparison = _compareData(blocks, previousBlocks, physicalBlockCount);
    evidence.addAll(comparison.evidence);

    String systemDetected;
    if (asciiMarkers.contains('INTRATONE')) {
      systemDetected = 'Intratone (indicator)';
    } else if (hexactKeyBlocks.isNotEmpty ||
        asciiMarkers.contains('HEXACT') ||
        asciiMarkers.contains('COGELEC')) {
      systemDetected = 'Hexact / Cogelec (indicator)';
    } else if (recurrentInstallerKey && allUpperDataZero) {
      systemDetected = 'Urmet / FDI (possible profile)';
    } else if (valueBlocks.isNotEmpty) {
      systemDetected = 'MIFARE Classic value block';
    } else {
      systemDetected = 'Unknown';
    }

    final combinedHexactIntratoneFingerprint =
        hexactKeyBlocks.isNotEmpty && asciiMarkers.contains('INTRATONE');
    final hasStaticClues =
        hexactKeyBlocks.isNotEmpty ||
        asciiMarkers.isNotEmpty ||
        (recurrentInstallerKey && allUpperDataZero) ||
        valueBlocks.isNotEmpty;
    final confidence = comparison.dynamicDataObserved == true
        ? DynamicBadgeConfidenceLevel.high
        : asciiMarkers.isNotEmpty && hexactKeyBlocks.isNotEmpty
        ? DynamicBadgeConfidenceLevel.medium
        : DynamicBadgeConfidenceLevel.low;
    final risk = comparison.dynamicDataObserved == true
        ? DynamicBadgeRiskLevel.critical
        : hasStaticClues
        ? DynamicBadgeRiskLevel.low
        : DynamicBadgeRiskLevel.none;

    final details = switch (comparison.dynamicDataObserved) {
      true =>
        'Data changed between comparable captures. A fixed copy may '
            'become stale; the cause of the change and any rolling-code '
            'mechanism remain unverified.',
      false =>
        'No data change was observed across two complete, comparable '
            'captures. This does not rule out later changes or a rolling code.',
      null => combinedHexactIntratoneFingerprint
          ? 'HEXACT-style Key A and an INTRATONE marker are both present. '
                'This is a strong system fingerprint, so badge-side writing '
                'is possible. The dump alone cannot establish whether this '
                'installation writes to the badge or uses a rolling code.'
          : 'The available captures do not establish whether the badge '
                'uses dynamic data or a rolling code. Static signatures and '
                'value blocks are only clues.',
    };

    return DynamicBadgeAnalysis(
      systemDetected: systemDetected,
      combinedHexactIntratoneFingerprint: combinedHexactIntratoneFingerprint,
      hasRollingCode: null,
      dynamicDataObserved: comparison.dynamicDataObserved,
      confidenceLevel: confidence,
      riskLevel: risk,
      details: comparison.note == null
          ? details
          : '$details ${comparison.note}',
      evidence: evidence,
    );
  }

  static _DataComparison _compareData(
    List<Uint8List> current,
    List<Uint8List>? previous,
    int physicalBlockCount,
  ) {
    if (previous == null) return const _DataComparison(null, [], null);
    if (identical(current, previous) ||
        current.length < physicalBlockCount ||
        previous.length < physicalBlockCount) {
      return const _DataComparison(null, [
        DynamicBadgeEvidence(
          code: 'comparison_limited',
          blockIndices: [],
          description:
              'Two independent dumps with the expected physical '
              'block count are required for comparison.',
        ),
      ], 'The supplied captures could not be compared fully.');
    }

    final currentBlock0 = _validBlock(current, 0, physicalBlockCount);
    final previousBlock0 = _validBlock(previous, 0, physicalBlockCount);
    if (currentBlock0 == null ||
        previousBlock0 == null ||
        _isZero(currentBlock0) ||
        _isZero(previousBlock0)) {
      return const _DataComparison(null, [
        DynamicBadgeEvidence(
          code: 'comparison_limited',
          blockIndices: [0],
          description:
              'A readable manufacturer/UID block is needed to '
              'compare captures from the same card.',
        ),
      ], 'Card identity could not be verified from block 0.');
    }
    if (!_sameBytes(currentBlock0, previousBlock0)) {
      return const _DataComparison(null, [
        DynamicBadgeEvidence(
          code: 'identity_mismatch',
          blockIndices: [0],
          description:
              'Manufacturer/UID blocks differ; these captures '
              'cannot be treated as the same card.',
        ),
      ], 'The manufacturer/UID blocks differ.');
    }

    final changed = <int>[];
    final limited = <int>[];
    var compared = 0;
    for (var index = 1; index < physicalBlockCount; index++) {
      if (_isTrailer(index)) continue;
      final now = _validBlock(current, index, physicalBlockCount);
      final before = _validBlock(previous, index, physicalBlockCount);
      if (now == null || before == null || _isZero(now) || _isZero(before)) {
        limited.add(index);
        continue;
      }
      compared++;
      if (!_sameBytes(now, before)) changed.add(index);
    }

    final evidence = <DynamicBadgeEvidence>[];
    if (changed.isNotEmpty) {
      evidence.add(
        DynamicBadgeEvidence(
          code: 'data_changed',
          blockIndices: changed,
          description:
              'Data changed in ${changed.length} readable '
              'non-trailer block(s) across captures of the same card. '
              'The mechanism behind the change is unknown.',
        ),
      );
    }
    if (limited.isNotEmpty) {
      evidence.add(
        DynamicBadgeEvidence(
          code: 'comparison_limited',
          blockIndices: limited,
          description:
              '${limited.length} data block(s) were missing or '
              'all-zero in at least one capture; they were not compared '
              'because zeroes may substitute for failed reads.',
        ),
      );
    }
    if (changed.isNotEmpty) {
      return _DataComparison(
        true,
        evidence,
        limited.isEmpty ? null : 'Some blocks were excluded from comparison.',
      );
    }
    if (limited.isNotEmpty || compared == 0) {
      return _DataComparison(
        null,
        evidence,
        'Unverified blocks prevent a conclusion about unchanged data.',
      );
    }
    evidence.add(
      DynamicBadgeEvidence(
        code: 'data_unchanged',
        blockIndices: const [],
        description:
            'All $compared readable physical data blocks were '
            'identical across the two captures.',
      ),
    );
    return _DataComparison(false, evidence, null);
  }

  static int _trailerBlock(int sector) =>
      sector < 32 ? sector * 4 + 3 : 128 + (sector - 32) * 16 + 15;

  static bool _isTrailer(int block) =>
      block < 128 ? block % 4 == 3 : (block - 128) % 16 == 15;

  static Uint8List? _validBlock(
    List<Uint8List> blocks,
    int index,
    int physicalBlockCount,
  ) {
    if (index < 0 || index >= physicalBlockCount || index >= blocks.length) {
      return null;
    }
    final block = blocks[index];
    return block.length == 16 ? block : null;
  }

  static bool _matchesKeyA(Uint8List trailer, List<int> key) {
    for (var index = 0; index < 6; index++) {
      if (trailer[index] != key[index]) return false;
    }
    return true;
  }

  static bool _isValueBlock(Uint8List block) {
    for (var index = 0; index < 4; index++) {
      if (block[index] != block[index + 8] ||
          block[index + 4] != (block[index] ^ 0xFF)) {
        return false;
      }
    }
    return block[12] == block[14] &&
        block[13] == block[15] &&
        block[12] == (block[13] ^ 0xFF);
  }

  static bool _isZero(Uint8List block) {
    for (final byte in block) {
      if (byte != 0) return false;
    }
    return true;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

class _DataComparison {
  final bool? dynamicDataObserved;
  final List<DynamicBadgeEvidence> evidence;
  final String? note;

  const _DataComparison(this.dynamicDataObserved, this.evidence, this.note);
}
