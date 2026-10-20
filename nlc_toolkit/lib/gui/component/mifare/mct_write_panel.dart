import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/bridge/chameleon.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/mct_write.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/mct_write_runner.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:provider/provider.dart';

enum _MctMode { block, dump, format, value }

/// Reproduces the MIFARE Classic Tool write modes against a Chameleon Ultra:
/// single block, full dump (clone) with manufacturer-block and static access
/// condition options, factory format, and value block increment/decrement.
class MctWritePanel extends StatefulWidget {
  const MctWritePanel({super.key});

  @override
  State<MctWritePanel> createState() => _MctWritePanelState();
}

class _MctWritePanelState extends State<MctWritePanel> {
  _MctMode _mode = _MctMode.dump;
  String? _cardId;
  final Set<String> _dictionaryIds = {};

  MctKeyMap? _keyMap;
  bool _busy = false;
  double? _progress;
  String? _status;

  // Dump / block options.
  bool _writeManufacturer = false;
  bool _writeTrailers = true;
  bool _useStaticAc = false;
  final _staticAcController = TextEditingController(text: 'FF078069');
  final Set<int> _selectedSectors = {};

  // Single block options.
  int? _block;
  final _blockDataController = TextEditingController();

  // Value block options.
  int? _valueBlock;
  bool _increment = true;
  final _amountController = TextEditingController(text: '1');

  @override
  void dispose() {
    _staticAcController.dispose();
    _blockDataController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  ChameleonCommunicator? get _communicator {
    final appState = context.read<ChameleonGUIState>();
    final connector = appState.connector;
    if (connector == null ||
        !connector.connected ||
        connector.device != ChameleonDevice.ultra) {
      return null;
    }
    return appState.communicator;
  }

  List<CardSave> get _mfcCards =>
      context
          .read<ChameleonGUIState>()
          .sharedPreferencesProvider
          .getCards()
          .where((card) => isMifareClassic(card.tag))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  CardSave? get _selectedCard {
    for (final card in _mfcCards) {
      if (card.id == _cardId) return card;
    }
    return null;
  }

  void _show(String message) {
    if (mounted) setState(() => _status = message);
  }

  List<Uint8List> _candidateKeys(AppLocalizations localizations) {
    final provider = context.read<ChameleonGUIState>().sharedPreferencesProvider;
    final dictionaries = provider.getDictionaries(keyLength: 12);
    final selected = dictionaries
        .where((dict) => _dictionaryIds.contains(dict.id))
        .expand((dict) => dict.keys);
    return mctCandidateKeys(selected, dump: _selectedCard);
  }

  Future<void> _mapKeys() async {
    final localizations = AppLocalizations.of(context)!;
    final communicator = _communicator;
    if (communicator == null) {
      _show(localizations.basic_write_connect_ultra);
      return;
    }
    final appState = context.read<ChameleonGUIState>();
    final chunkSize =
        appState.connector!.connectionType == ConnectionType.ble ? 32 : 64;
    setState(() {
      _busy = true;
      _status = null;
      _progress = 0;
      _keyMap = null;
    });
    try {
      final map = await mctMapKeys(
        communicator,
        _candidateKeys(localizations),
        chunkSize: chunkSize,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (map == null) {
        _show(localizations.not_mifare_classic_card);
        return;
      }
      final missing = [
        for (var s = 0; s < map.sectorCount; s++)
          if (!map.hasAnyKey(s)) s,
      ];
      setState(() => _keyMap = map);
      _show(
        '${localizations.mct_key_map_summary(bytesToHexSpace(map.uid), (map.sectorCount - missing.length).toString(), map.sectorCount.toString())}'
        '${missing.isEmpty ? '' : '\n${localizations.mct_keys_missing(missing.join(', '))}'}',
      );
    } catch (_) {
      _show(localizations.mct_write_error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<bool> _confirm(String title, String detail, String action) async {
    final localizations = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(detail),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(localizations.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ==
        true;
  }

  Uint8List? _staticAcBytes(AppLocalizations localizations) {
    if (!_useStaticAc) return null;
    final text = _staticAcController.text.trim();
    if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(text)) {
      _show(localizations.mct_static_ac_invalid);
      return null;
    }
    final bytes = hexToBytes(text);
    if (!mfClassicAccessConditionsValid(bytes.sublist(0, 3))) {
      _show(localizations.mct_static_ac_invalid);
      return null;
    }
    return bytes;
  }

  Future<void> _runPlan(MctWritePlan plan, String confirmDetail) async {
    final localizations = AppLocalizations.of(context)!;
    final communicator = _communicator;
    final keyMap = _keyMap;
    if (communicator == null) {
      _show(localizations.basic_write_connect_ultra);
      return;
    }
    if (keyMap == null) {
      _show(localizations.mct_key_map_required);
      return;
    }
    if (plan.blockCount == 0) {
      _show(localizations.mct_nothing_to_write);
      return;
    }
    if (!await _confirm(
      localizations.mct_confirm_title,
      confirmDetail,
      localizations.write,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = null;
      _progress = 0;
    });
    try {
      final report = await mctRunWritePlan(
        communicator,
        plan,
        keyMap,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (report.cardChanged) {
        _show(localizations.mct_card_changed);
        return;
      }
      final failed = [
        for (final entry in report.blocks.entries)
          if (entry.value == MctBlockOutcome.failed ||
              entry.value == MctBlockOutcome.noKey)
            entry.key,
      ]..sort();
      final lines = <String>[
        localizations.mct_report(
          report.count(MctBlockOutcome.verified).toString(),
          report.count(MctBlockOutcome.written).toString(),
          report.count(MctBlockOutcome.failed).toString(),
          report.count(MctBlockOutcome.noKey).toString(),
        ),
        if (plan.invalidTrailerSectors.isNotEmpty)
          localizations.mct_skipped_trailers(
            plan.invalidTrailerSectors.join(', '),
          ),
        if (failed.isNotEmpty)
          localizations.mct_failed_blocks(failed.join(', ')),
      ];
      _show(lines.join('\n'));
      if (mounted) context.read<ChameleonGUIState>().changesMade();
    } catch (_) {
      _show(localizations.mct_write_error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _writeDump() async {
    final localizations = AppLocalizations.of(context)!;
    final card = _selectedCard;
    final keyMap = _keyMap;
    if (card == null || keyMap == null) {
      _show(localizations.mct_key_map_required);
      return;
    }
    if (_useStaticAc && _staticAcBytes(localizations) == null) return;
    final MctWritePlan plan;
    try {
      plan = buildMctDumpWritePlan(
        card,
        MctWriteOptions(
          sectors: _selectedSectors.isEmpty
              ? mctSectorsWithData(card).toSet()
              : _selectedSectors,
          writeManufacturerBlock: _writeManufacturer,
          writeTrailers: _writeTrailers,
          staticAccessConditions: _staticAcBytes(localizations),
        ),
      );
    } catch (_) {
      _show(localizations.mct_static_ac_invalid);
      return;
    }
    if (plan.invalidManufacturerBlock) {
      _show(localizations.mct_manufacturer_invalid);
      return;
    }
    await _runPlan(
      plan,
      localizations.mct_confirm_detail(
        plan.blockCount.toString(),
        bytesToHexSpace(keyMap.uid),
      ),
    );
  }

  Future<void> _writeBlock() async {
    final localizations = AppLocalizations.of(context)!;
    final card = _selectedCard;
    final keyMap = _keyMap;
    if (card == null || keyMap == null) {
      _show(localizations.mct_key_map_required);
      return;
    }
    final block = _block;
    final text = _blockDataController.text.trim();
    if (block == null) {
      _show(localizations.mct_block_out_of_range);
      return;
    }
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(text)) {
      _show(localizations.mct_data_invalid);
      return;
    }
    if (block >= mfClassicGetBlockCount(keyMap.type)) {
      _show(localizations.mct_block_out_of_range);
      return;
    }
    final data = hexToBytes(text);
    final rejection = mctCheckBlockWrite(
      block,
      data,
      allowManufacturerBlock: _writeManufacturer,
      uidLength: keyMap.uid.length,
    );
    if (rejection != null) {
      _show(switch (rejection) {
        MctBlockRejection.manufacturerBlockLocked =>
          localizations.mct_manufacturer_locked,
        MctBlockRejection.invalidManufacturerBlock =>
          localizations.mct_manufacturer_invalid,
        MctBlockRejection.invalidAccessConditions => localizations.mct_ac_invalid,
      });
      return;
    }
    final sector = mfClassicGetSectorByBlock(block);
    final isTrailer = block == mfClassicGetSectorTrailerBlockBySector(sector);
    await _runPlan(
      MctWritePlan(
        blocksBySector: {
          sector: [MctWriteBlock(block, data, isTrailer: isTrailer)],
        },
      ),
      localizations.mct_confirm_detail('1', bytesToHexSpace(keyMap.uid)),
    );
  }

  Future<void> _format() async {
    final localizations = AppLocalizations.of(context)!;
    final keyMap = _keyMap;
    if (keyMap == null) {
      _show(localizations.mct_key_map_required);
      return;
    }
    final sectors = [
      for (var s = 0; s < keyMap.sectorCount; s++)
        if (keyMap.hasAnyKey(s)) s,
    ];
    if (!await _confirm(
      localizations.mct_confirm_title,
      localizations.mct_confirm_format(bytesToHexSpace(keyMap.uid)),
      localizations.mct_format_action,
    )) {
      return;
    }
    await _runPlan(
      buildFactoryFormatPlan(sectors),
      localizations.mct_confirm_format(bytesToHexSpace(keyMap.uid)),
    );
  }

  Future<void> _changeValueBlock() async {
    final localizations = AppLocalizations.of(context)!;
    final communicator = _communicator;
    final keyMap = _keyMap;
    if (communicator == null) {
      _show(localizations.basic_write_connect_ultra);
      return;
    }
    if (keyMap == null) {
      _show(localizations.mct_key_map_required);
      return;
    }
    final block = _valueBlock;
    final amount = int.tryParse(_amountController.text.trim());
    if (block == null) {
      _show(localizations.mct_value_block_invalid);
      return;
    }
    final sector = mfClassicGetSectorByBlock(block);
    if (block == 0 ||
        block == mfClassicGetSectorTrailerBlockBySector(sector)) {
      _show(localizations.mct_value_block_invalid);
      return;
    }
    if (amount == null || amount < 1 || amount > 0x7FFFFFFF) {
      _show(localizations.mct_value_amount_invalid);
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final ok = await mctChangeValueBlock(
        communicator,
        keyMap,
        block,
        _increment
            ? MifareClassicValueBlockOperator.increment
            : MifareClassicValueBlockOperator.decrement,
        amount,
      );
      if (!ok) {
        _show(localizations.mct_value_failed);
        return;
      }
      int? value;
      for (final (keyType, key) in keyMap.keysFor(sector)) {
        try {
          final data = await communicator.mf1ReadBlock(block, keyType, key);
          if (data.length == 16) {
            var raw = data[0] | data[1] << 8 | data[2] << 16 | data[3] << 24;
            if (raw > 0x7FFFFFFF) raw -= 0x100000000;
            value = raw;
            break;
          }
        } catch (_) {}
      }
      _show(
        value == null
            ? localizations.mct_value_done
            : localizations.mct_value_result(value.toString()),
      );
      if (mounted) context.read<ChameleonGUIState>().changesMade();
    } catch (_) {
      _show(localizations.mct_write_error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final card = _selectedCard;
    // A saved card is needed for everything except the factory format.
    final needsCard = _mode != _MctMode.format;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localizations.mct_write_title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              localizations.mct_write_description,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SegmentedButton<_MctMode>(
              segments: [
                ButtonSegment(
                  value: _MctMode.dump,
                  label: Text(localizations.mct_mode_dump),
                ),
                ButtonSegment(
                  value: _MctMode.block,
                  label: Text(localizations.mct_mode_block),
                ),
                ButtonSegment(
                  value: _MctMode.format,
                  label: Text(localizations.mct_mode_format),
                ),
                ButtonSegment(
                  value: _MctMode.value,
                  label: Text(localizations.mct_mode_value),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _mode = value.first;
                      _status = null;
                    }),
            ),
            const SizedBox(height: 20),
            if (needsCard) _buildCardPicker(localizations, card),
            _buildKeyMapSection(localizations),
            const Divider(height: 32),
            switch (_mode) {
              _MctMode.dump => _buildDumpOptions(localizations, card),
              _MctMode.block => _buildBlockOptions(localizations, card),
              _MctMode.format => _buildFormatOptions(localizations),
              _MctMode.value => _buildValueOptions(localizations, card),
            },
            if (_progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
            ],
            if (_status != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_status!)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCardPicker(AppLocalizations localizations, CardSave? card) {
    final cards = _mfcCards;
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(localizations.basic_write_no_dumps),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('mct-dump-${card?.id ?? 'none'}'),
        initialValue: card?.id,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: localizations.select_saved_card,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final c in cards)
            DropdownMenuItem(
              value: c.id,
              child: Text(c.name.isEmpty ? c.uid : c.name),
            ),
        ],
        onChanged: _busy
            ? null
            : (value) => setState(() {
                _cardId = value;
                _block = null;
                _valueBlock = null;
                _selectedSectors.clear();
                _status = null;
              }),
      ),
    );
  }

  Widget _buildKeyMapSection(AppLocalizations localizations) {
    final provider = context.read<ChameleonGUIState>().sharedPreferencesProvider;
    final dictionaries = provider.getDictionaries(keyLength: 12);
    final map = _keyMap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.mct_key_map,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          localizations.mct_key_map_description,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (dictionaries.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final dict in dictionaries)
                FilterChip(
                  label: Text(dict.name),
                  selected: _dictionaryIds.contains(dict.id),
                  onSelected: _busy
                      ? null
                      : (selected) => setState(() {
                          if (selected) {
                            _dictionaryIds.add(dict.id);
                          } else {
                            _dictionaryIds.remove(dict.id);
                          }
                        }),
                ),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _mapKeys,
              icon: const Icon(Icons.vpn_key_outlined),
              label: Text(localizations.mct_map_keys),
            ),
            const SizedBox(width: 12),
            if (map != null)
              Expanded(
                child: Text(
                  localizations.mct_key_map_summary(
                    bytesToHexSpace(map.uid),
                    [
                      for (var s = 0; s < map.sectorCount; s++)
                        if (map.hasAnyKey(s)) s,
                    ].length.toString(),
                    map.sectorCount.toString(),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDumpOptions(AppLocalizations localizations, CardSave? card) {
    final sectors = card == null ? <int>[] : mctSectorsWithData(card);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.mct_mode_dump,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _writeTrailers,
          onChanged: _busy
              ? null
              : (v) => setState(() => _writeTrailers = v),
          title: Text(localizations.mct_write_trailers),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _writeManufacturer,
          onChanged: _busy
              ? null
              : (v) => setState(() => _writeManufacturer = v),
          title: Text(localizations.mct_write_manufacturer),
          subtitle: Text(localizations.mct_write_manufacturer_hint),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _useStaticAc,
          onChanged: (_busy || !_writeTrailers)
              ? null
              : (v) => setState(() => _useStaticAc = v),
          title: Text(localizations.mct_static_ac),
        ),
        if (_useStaticAc && _writeTrailers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _staticAcController,
              enabled: !_busy,
              maxLength: 8,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
              ],
              decoration: InputDecoration(
                labelText: localizations.mct_static_ac_field,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        if (sectors.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                localizations.mct_sectors_to_write,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _selectedSectors
                      ..clear()
                      ..addAll(sectors)),
                child: Text(localizations.mct_select_all),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _selectedSectors.clear()),
                child: Text(localizations.mct_select_none),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final sector in sectors)
                FilterChip(
                  label: Text('$sector'),
                  selected: _selectedSectors.isEmpty ||
                      _selectedSectors.contains(sector),
                  onSelected: _busy
                      ? null
                      : (selected) => setState(() {
                          if (_selectedSectors.isEmpty) {
                            _selectedSectors.addAll(sectors);
                          }
                          if (selected) {
                            _selectedSectors.add(sector);
                          } else {
                            _selectedSectors.remove(sector);
                          }
                        }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: (_busy || card == null || _keyMap == null)
              ? null
              : _writeDump,
          icon: const Icon(Icons.save_alt),
          label: Text(localizations.write),
        ),
      ],
    );
  }

  Widget _buildBlockOptions(AppLocalizations localizations, CardSave? card) {
    final blocks = card == null
        ? <int>[]
        : [
            for (var b = 0; b < card.data.length; b++)
              if (card.data[b].length == 16) b,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.mct_mode_block,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (blocks.isNotEmpty)
          DropdownButtonFormField<int>(
            key: ValueKey('mct-block-${card?.id}'),
            initialValue: blocks.contains(_block) ? _block : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: localizations.mct_block_in_sector,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final block in blocks)
                DropdownMenuItem(
                  value: block,
                  child: Text(
                    '${localizations.block} $block · ${localizations.sector} ${mfClassicGetSectorByBlock(block)}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _block = value;
                    if (value != null && value < card!.data.length) {
                      _blockDataController.text =
                          bytesToHex(card.data[value]).toUpperCase();
                    }
                    _status = null;
                  }),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _blockDataController,
          enabled: !_busy,
          maxLength: 32,
          autocorrect: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
          ],
          decoration: InputDecoration(
            labelText: localizations.mct_data,
            border: const OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _writeManufacturer,
          onChanged: _busy
              ? null
              : (v) => setState(() => _writeManufacturer = v),
          title: Text(localizations.mct_write_manufacturer),
          subtitle: Text(localizations.mct_write_manufacturer_hint),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_busy || card == null || _keyMap == null)
              ? null
              : _writeBlock,
          icon: const Icon(Icons.draw_outlined),
          label: Text(localizations.write),
        ),
      ],
    );
  }

  Widget _buildFormatOptions(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.mct_mode_format,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(localizations.mct_format_description),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: (_busy || _keyMap == null) ? null : _format,
          icon: const Icon(Icons.restart_alt),
          label: Text(localizations.mct_format_action),
        ),
      ],
    );
  }

  Widget _buildValueOptions(AppLocalizations localizations, CardSave? card) {
    final blocks = card == null
        ? <int>[]
        : [
            for (var b = 1; b < card.data.length; b++)
              if (card.data[b].length == 16 &&
                  b !=
                      mfClassicGetSectorTrailerBlockBySector(
                        mfClassicGetSectorByBlock(b),
                      ))
                b,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.mct_mode_value,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (blocks.isNotEmpty)
          DropdownButtonFormField<int>(
            key: ValueKey('mct-value-${card?.id}'),
            initialValue: blocks.contains(_valueBlock) ? _valueBlock : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: localizations.mct_block_in_sector,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final block in blocks)
                DropdownMenuItem(
                  value: block,
                  child: Text(
                    '${localizations.block} $block · ${localizations.sector} ${mfClassicGetSectorByBlock(block)}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _valueBlock = value;
                    _status = null;
                  }),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(localizations.mct_increment),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(localizations.mct_decrement),
                  ),
                ],
                selected: {_increment},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() => _increment = value.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: localizations.mct_value_amount,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_busy || card == null || _keyMap == null)
              ? null
              : _changeValueBlock,
          icon: const Icon(Icons.exposure),
          label: Text(localizations.mct_value_action),
        ),
      ],
    );
  }
}
