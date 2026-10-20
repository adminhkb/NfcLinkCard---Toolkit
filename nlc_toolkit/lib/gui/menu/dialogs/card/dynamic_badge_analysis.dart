import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/dynamic_badge_analyzer.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/rolling_code_detector.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

enum _SequenceRole { idleControl, afterFirstUse, afterSecondUse }

/// Read-only interpretation of one saved MIFARE Classic dump, with an optional
/// comparison against another saved reading of the same card.
class DynamicBadgeAnalysisDialog extends StatefulWidget {
  final CardSave cardSave;
  final List<CardSave> savedCards;
  final bool hasUnsavedChanges;

  const DynamicBadgeAnalysisDialog({
    super.key,
    required this.cardSave,
    required this.savedCards,
    required this.hasUnsavedChanges,
  });

  @override
  State<DynamicBadgeAnalysisDialog> createState() =>
      _DynamicBadgeAnalysisDialogState();
}

class _DynamicBadgeAnalysisDialogState
    extends State<DynamicBadgeAnalysisDialog> {
  late DynamicBadgeAnalysis _analysis;
  CardSave? _comparisonCard;
  CardSave? _idleControl;
  CardSave? _afterFirstUse;
  CardSave? _afterSecondUse;
  bool _usesConfirmed = false;

  int get _physicalBlockCount =>
      widget.cardSave.tag == TagType.mifare4K ? 256 : 64;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  void _analyze() {
    _analysis = DynamicBadgeAnalyzer.analyze(
      widget.cardSave.data,
      previousBlocks: _comparisonCard?.data,
      physicalBlockCount: _physicalBlockCount,
    );
  }

  // Only formatting separators may be removed. Invalid UID text is never
  // treated as a match, even if it happens to contain the same hex digits.
  String? _normalizedUid(String uid) {
    final normalized = uid.replaceAll(RegExp(r'[\s:\-]'), '').toUpperCase();
    if (!RegExp(r'^(?:[0-9A-F]{2})+$').hasMatch(normalized)) return null;
    return normalized;
  }

  List<CardSave> get _comparisonCandidates {
    final originalUid = _normalizedUid(widget.cardSave.uid);
    if (originalUid == null) return const [];
    return widget.savedCards
        .where(
          (card) =>
              card.id != widget.cardSave.id &&
              card.tag == widget.cardSave.tag &&
              _normalizedUid(card.uid) == originalUid,
        )
        .toList();
  }

  List<CardSave> _sequenceCandidates(_SequenceRole role) {
    final usedIds = <String>{
      widget.cardSave.id,
      if (role != _SequenceRole.idleControl && _idleControl != null)
        _idleControl!.id,
      if (role != _SequenceRole.afterFirstUse && _afterFirstUse != null)
        _afterFirstUse!.id,
      if (role != _SequenceRole.afterSecondUse && _afterSecondUse != null)
        _afterSecondUse!.id,
    };
    return _comparisonCandidates
        .where((card) => !usedIds.contains(card.id))
        .toList();
  }

  CardSave? _selectedSequenceCard(_SequenceRole role) => switch (role) {
    _SequenceRole.idleControl => _idleControl,
    _SequenceRole.afterFirstUse => _afterFirstUse,
    _SequenceRole.afterSecondUse => _afterSecondUse,
  };

  RollingCodeSequenceResult? get _sequenceResult {
    if (_afterFirstUse == null || _afterSecondUse == null) return null;
    return RollingCodeDetector.analyze(
      before: widget.cardSave.data,
      idleControl: _idleControl?.data,
      afterFirstUse: _afterFirstUse!.data,
      afterSecondUse: _afterSecondUse!.data,
      physicalBlockCount: _physicalBlockCount,
      usesConfirmed: _usesConfirmed,
    );
  }

  Future<void> _chooseSequenceScan(_SequenceRole role) async {
    final l10n = AppLocalizations.of(context)!;
    final candidates = _sequenceCandidates(role);
    if (candidates.isEmpty) return;
    final selected = await showDialog<CardSave>(
      context: context,
      builder: (pickerContext) => AlertDialog(
        title: Text(l10n.dynamic_select_scan_title),
        content: SizedBox(
          width: 430,
          height: 300,
          child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final card = candidates[index];
              return ListTile(
                leading: Icon(Icons.credit_card_outlined, color: card.color),
                title: Text(
                  card.name.trim().isEmpty
                      ? l10n.dynamic_unnamed_scan
                      : card.name,
                ),
                subtitle: Text(card.uid),
                selected: card.id == _selectedSequenceCard(role)?.id,
                onTap: () => Navigator.of(pickerContext).pop(card),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(pickerContext).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      switch (role) {
        case _SequenceRole.idleControl:
          _idleControl = selected;
          break;
        case _SequenceRole.afterFirstUse:
          if (_afterFirstUse?.id != selected.id) _usesConfirmed = false;
          _afterFirstUse = selected;
          break;
        case _SequenceRole.afterSecondUse:
          if (_afterSecondUse?.id != selected.id) _usesConfirmed = false;
          _afterSecondUse = selected;
          break;
      }
    });
  }

  void _removeSequenceScan(_SequenceRole role) {
    setState(() {
      switch (role) {
        case _SequenceRole.idleControl:
          _idleControl = null;
          break;
        case _SequenceRole.afterFirstUse:
          _afterFirstUse = null;
          _usesConfirmed = false;
          break;
        case _SequenceRole.afterSecondUse:
          _afterSecondUse = null;
          _usesConfirmed = false;
          break;
      }
    });
  }

  Future<void> _chooseComparison() async {
    final l10n = AppLocalizations.of(context)!;
    final candidates = _comparisonCandidates;
    if (candidates.isEmpty) return;
    final selected = await showDialog<CardSave>(
      context: context,
      builder: (pickerContext) => AlertDialog(
        title: Text(l10n.dynamic_select_scan_title),
        content: SizedBox(
          width: 430,
          height: 300,
          child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final card = candidates[index];
              return ListTile(
                leading: Icon(Icons.credit_card_outlined, color: card.color),
                title: Text(
                  card.name.trim().isEmpty
                      ? l10n.dynamic_unnamed_scan
                      : card.name,
                ),
                subtitle: Text(card.uid),
                selected: card.id == _comparisonCard?.id,
                onTap: () => Navigator.of(pickerContext).pop(card),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(pickerContext).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _comparisonCard = selected;
      _analyze();
    });
  }

  void _removeComparison() {
    setState(() {
      _comparisonCard = null;
      _analyze();
    });
  }

  bool get _hasInstallerKeyPattern =>
      _analysis.evidence.any((item) => item.code == 'installer_key_pattern');

  bool get _hasSystemFingerprint =>
      _analysis.evidence.any(
        (item) => item.code == 'hexact_key' || item.code == 'ascii_marker',
      ) ||
      (_hasInstallerKeyPattern &&
          _analysis.evidence.any((item) => item.code == 'zero_upper_data'));

  String _statusLabel(AppLocalizations l10n) {
    if (_analysis.dynamicDataObserved == true) {
      return l10n.dynamic_status_changed;
    }
    if (_analysis.dynamicDataObserved == false) {
      return l10n.dynamic_status_unchanged;
    }
    if (_hasSystemFingerprint) return l10n.dynamic_status_fingerprint;
    if (_hasInstallerKeyPattern) return l10n.dynamic_status_key_pattern;
    return l10n.dynamic_status_indeterminate;
  }

  String _statusExplanation(AppLocalizations l10n) {
    if (_analysis.dynamicDataObserved == true) {
      return l10n.dynamic_status_changed_detail;
    }
    if (_analysis.dynamicDataObserved == false) {
      return l10n.dynamic_status_unchanged_detail;
    }
    if (_hasSystemFingerprint) return l10n.dynamic_status_fingerprint_detail;
    if (_hasInstallerKeyPattern) {
      return l10n.dynamic_status_key_pattern_detail;
    }
    return l10n.dynamic_status_indeterminate_detail;
  }

  Color _statusColor() {
    if (_analysis.dynamicDataObserved == true) {
      return const Color(0xFFF2AF52);
    }
    if (_analysis.dynamicDataObserved == false) {
      return const Color(0xFF91A5BA);
    }
    if (_hasSystemFingerprint) return const Color(0xFF35C7E8);
    return const Color(0xFF91A5BA);
  }

  String _profileLabel(AppLocalizations l10n) {
    switch (_analysis.systemDetected) {
      case 'Intratone (indicator)':
        return l10n.dynamic_profile_intratone;
      case 'Hexact / Cogelec (indicator)':
        return l10n.dynamic_profile_hexact;
      case 'Urmet / FDI (possible profile)':
        return l10n.dynamic_profile_urmet;
      case 'MIFARE Classic value block':
        return l10n.dynamic_profile_value_block;
      default:
        return l10n.dynamic_profile_unknown;
    }
  }

  String _confidenceLabel(AppLocalizations l10n) {
    switch (_analysis.confidenceLevel) {
      case DynamicBadgeConfidenceLevel.high:
        return l10n.dynamic_confidence_high;
      case DynamicBadgeConfidenceLevel.medium:
        return l10n.dynamic_confidence_medium;
      case DynamicBadgeConfidenceLevel.low:
        return l10n.dynamic_confidence_low;
    }
  }

  String _riskLabel(AppLocalizations l10n) {
    switch (_analysis.riskLevel) {
      case DynamicBadgeRiskLevel.critical:
        return l10n.dynamic_risk_high;
      case DynamicBadgeRiskLevel.low:
        return l10n.dynamic_risk_caution;
      case DynamicBadgeRiskLevel.none:
        return l10n.dynamic_risk_unevaluated;
    }
  }

  String _rollingCodeLabel(AppLocalizations l10n) {
    if (_analysis.hasRollingCode == true) return l10n.dynamic_rolling_detected;
    if (_analysis.hasRollingCode == false) {
      return l10n.dynamic_rolling_not_detected;
    }
    return l10n.dynamic_rolling_indeterminate;
  }

  String _evidenceLabel(AppLocalizations l10n, DynamicBadgeEvidence item) {
    switch (item.code) {
      case 'hexact_key':
        return l10n.dynamic_evidence_hexact_key;
      case 'ascii_marker':
        return l10n.dynamic_evidence_ascii_marker;
      case 'installer_key_pattern':
        return l10n.dynamic_evidence_installer_key;
      case 'zero_upper_data':
        return l10n.dynamic_evidence_zero_upper;
      case 'value_block':
        return l10n.dynamic_evidence_value_block;
      case 'data_changed':
        return l10n.dynamic_evidence_data_changed;
      case 'data_unchanged':
        return l10n.dynamic_evidence_data_unchanged;
      case 'comparison_limited':
        return l10n.dynamic_evidence_comparison_limited;
      case 'identity_mismatch':
        return l10n.dynamic_evidence_identity_mismatch;
      default:
        return l10n.dynamic_evidence_other;
    }
  }

  Widget _summaryTile(String title, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _notice(IconData icon, String text, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  String _sequenceRoleLabel(AppLocalizations l10n, _SequenceRole role) =>
      switch (role) {
        _SequenceRole.idleControl => l10n.dynamic_sequence_idle_label,
        _SequenceRole.afterFirstUse => l10n.dynamic_sequence_first_label,
        _SequenceRole.afterSecondUse => l10n.dynamic_sequence_second_label,
      };

  Widget _sequenceScanRow(AppLocalizations l10n, _SequenceRole role) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedSequenceCard(role);
    final candidates = _sequenceCandidates(role);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sequenceRoleLabel(l10n, role),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  selected == null
                      ? l10n.dynamic_sequence_not_selected
                      : selected.name.trim().isEmpty
                      ? l10n.dynamic_unnamed_scan
                      : selected.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: candidates.isEmpty
                ? null
                : () => _chooseSequenceScan(role),
            child: Text(l10n.dynamic_sequence_choose),
          ),
          if (selected != null)
            IconButton(
              tooltip: l10n.dynamic_sequence_remove,
              onPressed: () => _removeSequenceScan(role),
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }

  String _sequenceVerdictLabel(
    AppLocalizations l10n,
    RollingCodeSequenceVerdict verdict,
  ) => switch (verdict) {
    RollingCodeSequenceVerdict.insufficient =>
      l10n.dynamic_sequence_insufficient,
    RollingCodeSequenceVerdict.noChangeObserved =>
      l10n.dynamic_sequence_no_change,
    RollingCodeSequenceVerdict.dataChanged =>
      l10n.dynamic_sequence_data_changed,
    RollingCodeSequenceVerdict.repeatedChange =>
      l10n.dynamic_sequence_repeated_change,
    RollingCodeSequenceVerdict.rollingCompatible =>
      l10n.dynamic_sequence_compatible,
  };

  String _sequenceVerdictDetail(
    AppLocalizations l10n,
    RollingCodeSequenceVerdict verdict,
  ) => switch (verdict) {
    RollingCodeSequenceVerdict.insufficient =>
      l10n.dynamic_sequence_insufficient_detail,
    RollingCodeSequenceVerdict.noChangeObserved =>
      l10n.dynamic_sequence_no_change_detail,
    RollingCodeSequenceVerdict.dataChanged =>
      l10n.dynamic_sequence_data_changed_detail,
    RollingCodeSequenceVerdict.repeatedChange =>
      l10n.dynamic_sequence_repeated_change_detail,
    RollingCodeSequenceVerdict.rollingCompatible =>
      l10n.dynamic_sequence_compatible_detail,
  };

  Widget _sequenceBlocksRow(String label, List<int> blocks) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '$label ${blocks.join(', ')}',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
    );
  }

  Widget _sequenceSection(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final result = _sequenceResult;
    final hasBothAfterScans = _afterFirstUse != null && _afterSecondUse != null;
    final warning = const Color(0xFFF2AF52);
    final resultColor =
        result?.verdict == RollingCodeSequenceVerdict.rollingCompatible
        ? warning
        : result?.verdict == RollingCodeSequenceVerdict.repeatedChange ||
              result?.verdict == RollingCodeSequenceVerdict.dataChanged
        ? scheme.primary
        : scheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.48),
        ),
      ),
      child: ExpansionTile(
        key: const PageStorageKey<String>('dynamic-sequence-analysis'),
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(l10n.dynamic_sequence_title),
        subtitle: Text(
          result == null
              ? l10n.dynamic_sequence_optional_summary
              : _sequenceVerdictLabel(l10n, result.verdict),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.dynamic_sequence_help,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.42),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.looks_one_outlined,
                      color: scheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${l10n.dynamic_sequence_before_label}: '
                        '${widget.cardSave.name.trim().isEmpty ? l10n.dynamic_unnamed_scan : widget.cardSave.name}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              _sequenceScanRow(l10n, _SequenceRole.idleControl),
              _sequenceScanRow(l10n, _SequenceRole.afterFirstUse),
              _sequenceScanRow(l10n, _SequenceRole.afterSecondUse),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _usesConfirmed,
                onChanged: (value) =>
                    setState(() => _usesConfirmed = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.dynamic_sequence_confirm_uses),
                subtitle: Text(l10n.dynamic_sequence_confirm_help),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: resultColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result == null
                          ? l10n.dynamic_sequence_insufficient
                          : _sequenceVerdictLabel(l10n, result.verdict),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: resultColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      result == null
                          ? l10n.dynamic_sequence_missing_scans
                          : !_usesConfirmed && hasBothAfterScans
                          ? l10n.dynamic_sequence_unconfirmed_uses
                          : _sequenceVerdictDetail(l10n, result.verdict),
                    ),
                    if (result != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        '${result.comparedBlockCount} '
                        '${l10n.dynamic_sequence_compared_blocks}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      _sequenceBlocksRow(
                        l10n.dynamic_sequence_first_blocks,
                        result.firstChangedBlocks,
                      ),
                      _sequenceBlocksRow(
                        l10n.dynamic_sequence_second_blocks,
                        result.secondChangedBlocks,
                      ),
                      _sequenceBlocksRow(
                        l10n.dynamic_sequence_repeated_blocks,
                        result.repeatedChangedBlocks,
                      ),
                      _sequenceBlocksRow(
                        l10n.dynamic_sequence_compatible_blocks,
                        result.rollingCompatibleBytesByBlock.keys.toList()
                          ..sort(),
                      ),
                      _sequenceBlocksRow(
                        l10n.dynamic_sequence_value_blocks,
                        result.valueChangedBlocks,
                      ),
                      _sequenceBlocksRow(
                        l10n.dynamic_sequence_ignored_blocks,
                        result.ignoredBlocks,
                      ),
                      _sequenceBlocksRow(
                        l10n.dynamic_sequence_control_blocks,
                        result.unstableControlBlocks,
                      ),
                      _sequenceBlocksRow(
                        l10n.dynamic_sequence_unverifiable_control_blocks,
                        result.unverifiableControlBlocks,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 9),
              _notice(Icons.info_outline, l10n.dynamic_sequence_central_caveat),
              const SizedBox(height: 8),
              _notice(Icons.info_outline, l10n.dynamic_sequence_zero_caveat),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor();
    final candidates = _comparisonCandidates;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 14, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.dynamic_badge_title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          l10n.dynamic_badge_subtitle,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_analysis.combinedHexactIntratoneFingerprint) ...[
                      Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2AF52)
                              .withValues(alpha: 0.11),
                          border: Border.all(
                            color: const Color(0xFFF2AF52)
                                .withValues(alpha: 0.55),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_outlined,
                              color: Color(0xFFF2AF52),
                              size: 23,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.dynamic_static_combo_title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: const Color(0xFFF2AF52),
                                        ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(l10n.dynamic_static_combo_detail),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (!_analysis.combinedHexactIntratoneFingerprint ||
                        _analysis.dynamicDataObserved != null)
                      Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.10),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.38),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: statusColor,
                              size: 23,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _statusLabel(l10n),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: statusColor),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(_statusExplanation(l10n)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        _summaryTile(
                          l10n.dynamic_profile_label,
                          _profileLabel(l10n),
                        ),
                        _summaryTile(
                          l10n.dynamic_rolling_label,
                          _rollingCodeLabel(l10n),
                        ),
                        if (_analysis.combinedHexactIntratoneFingerprint)
                          _summaryTile(
                            l10n.dynamic_static_write_label,
                            l10n.dynamic_static_write_unverified,
                          ),
                        _summaryTile(
                          l10n.dynamic_confidence_label,
                          _confidenceLabel(l10n),
                        ),
                        _summaryTile(l10n.dynamic_risk_label, _riskLabel(l10n)),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _sequenceSection(l10n),
                    const SizedBox(height: 22),
                    Text(
                      l10n.dynamic_evidence_title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 9),
                    if (_analysis.evidence.isEmpty)
                      Text(
                        l10n.dynamic_evidence_none,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    else
                      ..._analysis.evidence.map((item) {
                        final blocks = List<int>.from(item.blockIndices)
                          ..sort();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.tune,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_evidenceLabel(l10n, item)),
                                      if (blocks.isNotEmpty)
                                        Text(
                                          '${l10n.dynamic_evidence_blocks} ${blocks.join(', ')}',
                                          style: TextStyle(
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 13),
                    Text(
                      l10n.dynamic_comparison_title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.dynamic_comparison_help,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    if (_comparisonCard != null) ...[
                      const SizedBox(height: 9),
                      Text(
                        '${l10n.dynamic_comparison_selected} ${_comparisonCard!.name.trim().isEmpty ? l10n.dynamic_unnamed_scan : _comparisonCard!.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ] else if (candidates.isEmpty) ...[
                      const SizedBox(height: 9),
                      Text(
                        l10n.dynamic_comparison_none,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: candidates.isEmpty
                              ? null
                              : _chooseComparison,
                          icon: const Icon(Icons.compare_arrows),
                          label: Text(l10n.dynamic_choose_scan),
                        ),
                        if (_comparisonCard != null)
                          TextButton(
                            onPressed: _removeComparison,
                            child: Text(l10n.dynamic_remove_comparison),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _notice(
                      Icons.warning_amber_outlined,
                      l10n.dynamic_caveat_zero,
                      color: const Color(0xFFF2AF52),
                    ),
                    const SizedBox(height: 10),
                    _notice(
                      Icons.info_outline,
                      l10n.dynamic_caveat_interpretation,
                    ),
                    if (widget.hasUnsavedChanges) ...[
                      const SizedBox(height: 10),
                      _notice(Icons.edit_outlined, l10n.dynamic_caveat_unsaved),
                    ],
                    const SizedBox(height: 10),
                    _notice(Icons.lock_outline, l10n.dynamic_read_only),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.close),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
