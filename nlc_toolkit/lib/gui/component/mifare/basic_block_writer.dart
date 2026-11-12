import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Writes one data block from a saved MIFARE Classic dump to a physical tag.
class BasicMifareBlockWriter extends StatefulWidget {
  const BasicMifareBlockWriter({super.key});

  @override
  State<BasicMifareBlockWriter> createState() => _BasicMifareBlockWriterState();
}

class _BasicMifareBlockWriterState extends State<BasicMifareBlockWriter> {
  final TextEditingController _keyController = TextEditingController();
  String? _cardId;
  int? _block;
  int _keyType = 0x60;
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  List<int> _writableBlocks(CardSave card) {
    final maxBlocks = mfClassicGetBlockCount(
      chameleonTagTypeGetMfClassicType(card.tag),
    );
    final count = card.data.length < maxBlocks ? card.data.length : maxBlocks;
    return [
      for (var block = 1; block < count; block++)
        if (card.data[block].length == 16 &&
            block !=
                mfClassicGetSectorTrailerBlockBySector(
                  mfClassicGetSectorByBlock(block),
                ))
          block,
    ];
  }

  void _showStatus(String message) {
    if (mounted) {
      setState(() => _status = message);
    }
  }

  Future<void> _writeBlock(CardSave card, int block) async {
    if (_busy) return;
    final localizations = AppLocalizations.of(context)!;
    final appState = context.read<NlcAppState>();
    final connector = appState.connector;
    final communicator = appState.communicator;

    if (connector == null ||
        !connector.connected ||
        connector.device != ChameleonDevice.ultra ||
        communicator == null) {
      _showStatus(localizations.basic_write_connect_ultra);
      return;
    }

    final keyText = _keyController.text.trim();
    if (!RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(keyText)) {
      _showStatus(localizations.basic_write_invalid_key);
      return;
    }

    // Copy the bytes now so edits to the saved dump cannot alter this write.
    final bytesToWrite = Uint8List.fromList(card.data[block]);
    final key = hexToBytes(keyText);
    setState(() {
      _busy = true;
      _status = null;
    });

    bool writeAttempted = false;
    bool writeAccepted = false;
    try {
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }

      final target = await communicator.scan14443aTag();
      if (target == null) {
        _showStatus(localizations.no_card_found);
        return;
      }
      if (!await communicator.detectMf1Support()) {
        _showStatus(localizations.not_mifare_classic_card);
        return;
      }

      final targetType = await mfClassicGetType(communicator);
      if (block >= mfClassicGetBlockCount(targetType)) {
        _showStatus(localizations.basic_write_block_out_of_range);
        return;
      }
      if (!await communicator.mf1Auth(block, _keyType, key)) {
        _showStatus(localizations.basic_write_auth_failed);
        return;
      }
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(localizations.basic_write_confirm_title),
          content: Text(
            localizations.basic_write_confirm_detail(
              block,
              card.name.isEmpty ? card.uid : card.name,
              bytesToHexSpace(target.uid),
              _keyType == 0x60 ? 'A' : 'B',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(localizations.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(localizations.write),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      // A fresh scan prevents writing when the card was exchanged in the dialog.
      final beforeWrite = await communicator.scan14443aTag();
      if (beforeWrite == null || !listEquals(beforeWrite.uid, target.uid)) {
        _showStatus(localizations.basic_write_target_changed);
        return;
      }

      writeAttempted = true;
      if (!await communicator.mf1WriteBlock(
        block,
        _keyType,
        key,
        bytesToWrite,
      )) {
        _showStatus(localizations.basic_write_rejected);
        return;
      }
      writeAccepted = true;

      final beforeReadback = await communicator.scan14443aTag();
      if (beforeReadback == null ||
          !listEquals(beforeReadback.uid, target.uid)) {
        _showStatus(localizations.basic_write_readback_unavailable);
        return;
      }

      final readback = await communicator.mf1ReadBlock(block, _keyType, key);

      if (readback.length != 16) {
        _showStatus(localizations.basic_write_readback_unavailable);
      } else if (listEquals(readback, bytesToWrite)) {
        _showStatus(localizations.basic_write_verified);
      } else {
        _showStatus(localizations.basic_write_mismatch);
      }
    } catch (_) {
      _showStatus(
        writeAccepted
            ? localizations.basic_write_readback_unavailable
            : writeAttempted
            ? localizations.basic_write_error
            : localizations.basic_write_prewrite_error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.watch<NlcAppState>();
    final cards =
        appState.sharedPreferencesProvider
            .getCards()
            .where((card) => isMifareClassic(card.tag))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    CardSave? selectedCard;
    for (final card in cards) {
      if (card.id == _cardId) {
        selectedCard = card;
        break;
      }
    }
    final eligibleBlocks = selectedCard == null
        ? <int>[]
        : _writableBlocks(selectedCard);
    final selectedBlock = eligibleBlocks.contains(_block) ? _block : null;
    final data = selectedCard != null && selectedBlock != null
        ? selectedCard.data[selectedBlock]
        : null;

    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WriteStepHeading(
                number: '01',
                title: localizations.select_saved_card,
                active: true,
              ),
              const SizedBox(height: 16),
              if (cards.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(localizations.basic_write_no_dumps)),
                    ],
                  ),
                )
              else ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('dump-${selectedCard?.id ?? 'none'}'),
                  initialValue: selectedCard?.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: localizations.select_saved_card,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final card in cards)
                      DropdownMenuItem(
                        value: card.id,
                        child: Text(card.name.isEmpty ? card.uid : card.name),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _cardId = value;
                          _block = null;
                          _keyController.clear();
                          _status = null;
                        }),
                ),
                if (selectedCard != null) ...[
                  const SizedBox(height: 28),
                  _WriteStepHeading(
                    number: '02',
                    title: localizations.block,
                    active: true,
                  ),
                  const SizedBox(height: 14),
                  if (eligibleBlocks.isEmpty)
                    Text(localizations.basic_write_no_blocks)
                  else
                    DropdownButtonFormField<int>(
                      key: ValueKey('block-${selectedCard.id}'),
                      initialValue: selectedBlock,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: localizations.block,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final block in eligibleBlocks)
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
                              _keyController.clear();
                              _status = null;
                            }),
                    ),
                ],
                if (data != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    localizations.basic_write_data,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: SelectableText(
                      bytesToHexSpace(data),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _WriteStepHeading(
                    number: '03',
                    title: localizations.basic_write_key,
                    active: true,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: _keyType,
                    decoration: InputDecoration(
                      labelText: localizations.basic_write_key_type,
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0x60, child: Text('A')),
                      DropdownMenuItem(value: 0x61, child: Text('B')),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _keyType = value ?? 0x60;
                            _status = null;
                          }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _keyController,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 12,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    ],
                    decoration: InputDecoration(
                      labelText: localizations.basic_write_key,
                      hintText: localizations.basic_write_key_hint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _writeBlock(selectedCard!, selectedBlock!),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.draw_outlined),
                    label: Text(localizations.basic_write_action),
                  ),
                ],
              ],
              if (_status != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_status!)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WriteStepHeading extends StatelessWidget {
  const _WriteStepHeading({
    required this.number,
    required this.title,
    required this.active,
  });

  final String number;
  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.primary : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            number,
            style: TextStyle(
              color: active ? colors.onPrimary : colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}
