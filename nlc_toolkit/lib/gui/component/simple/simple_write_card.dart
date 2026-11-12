// Carte « Écrire » du mode simplifié : clonage guidé en un bouton, affiché
// directement sur l'accueil (ou dans la page d'écriture simple). Vérification des
// clés avec le dictionnaire MCT étendu, puis écriture de tout le dump (trailers et
// bloc constructeur compris, comme une carte magique Gen2). L'utilisateur ne voit
// qu'une barre de progression puis un résumé.
import 'package:flutter/material.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/mct_write.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/mct_write_runner.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:provider/provider.dart';

class SimpleWriteCard extends StatefulWidget {
  const SimpleWriteCard({super.key, this.initialCard});

  /// Dump pré-sélectionné comme source (sinon l'utilisateur choisit dans la liste).
  final CardSave? initialCard;

  @override
  State<SimpleWriteCard> createState() => _SimpleWriteCardState();
}

class _SimpleWriteCardState extends State<SimpleWriteCard> {
  CardSave? _card;
  bool _busy = false;
  double? _progress;
  String? _status;
  bool _done = false;
  bool _writing = false; // false = vérification des clés, true = écriture
  int _okBlocks = 0;
  int _failedBlocks = 0;

  @override
  void initState() {
    super.initState();
    _card = widget.initialCard;
  }

  List<CardSave> get _savedMfcCards =>
      context
          .read<NlcAppState>()
          .sharedPreferencesProvider
          .getCards()
          .where((c) => isMifareClassic(c.tag))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> _write(NlcAppState appState, AppLocalizations l) async {
    final source = _card;
    if (source == null) return;

    final connector = appState.connector;
    if (connector == null ||
        !connector.connected ||
        connector.device != ChameleonDevice.ultra) {
      if (connector?.device == ChameleonDevice.lite) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l.no_supported),
            content: Text(l.lite_no_read),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l.ok),
              ),
            ],
          ),
        );
      } else {
        setState(() => _status = l.basic_write_connect_ultra);
      }
      return;
    }

    final communicator = appState.communicator!;
    final chunkSize =
        connector.connectionType == ConnectionType.ble ? 32 : 64;

    setState(() {
      _busy = true;
      _done = false;
      _status = null;
      _progress = 0;
      _writing = false;
    });

    try {
      // 1. Vérification du dictionnaire MCT étendu (repli : MCT standard).
      final dictionaries = appState.sharedPreferencesProvider.getDictionaries(
        keyLength: 12,
      );
      Iterable<Dictionary> selected = dictionaries.where(
        (d) => d.id == 'mct-extended-std',
      );
      if (selected.isEmpty) {
        selected = dictionaries.where((d) => d.id == 'mct-std');
      }
      final dictKeys = selected.expand((d) => d.keys);
      final candidates = mctCandidateKeys(dictKeys, dump: source);

      // 2. Carte des clés de la carte cible.
      final keyMap = await mctMapKeys(
        communicator,
        candidates,
        chunkSize: chunkSize,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (keyMap == null) {
        setState(() => _status = l.not_mifare_classic_card);
        return;
      }

      // 3. Plan d'écriture : tous les secteurs porteurs de données, trailers et
      //    bloc constructeur (bloc 0) compris.
      setState(() {
        _writing = true;
        _progress = 0;
      });
      var plan = buildMctDumpWritePlan(
        source,
        MctWriteOptions(
          sectors: mctSectorsWithData(source).toSet(),
          writeManufacturerBlock: true,
          writeTrailers: true,
        ),
      );
      if (plan.invalidManufacturerBlock) {
        plan = buildMctDumpWritePlan(
          source,
          MctWriteOptions(
            sectors: mctSectorsWithData(source).toSet(),
            writeManufacturerBlock: false,
            writeTrailers: true,
          ),
        );
      }
      if (plan.blockCount == 0) {
        setState(() => _status = l.mct_nothing_to_write);
        return;
      }

      // 4. Écriture des données.
      final report = await mctRunWritePlan(
        communicator,
        plan,
        keyMap,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (report.cardChanged) {
        setState(() => _status = l.mct_card_changed);
        return;
      }
      setState(() {
        _okBlocks =
            report.count(MctBlockOutcome.verified) +
            report.count(MctBlockOutcome.written);
        _failedBlocks =
            report.count(MctBlockOutcome.failed) +
            report.count(MctBlockOutcome.noKey);
        _done = true;
      });
      appState.changesMade();
    } catch (_) {
      if (mounted) setState(() => _status = l.mct_write_error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _done = false;
      _status = null;
      _okBlocks = 0;
      _failedBlocks = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final appState = context.watch<NlcAppState>();
    final theme = Theme.of(context);
    final french = Localizations.localeOf(context).languageCode == 'fr';
    final cards = _savedMfcCards;

    Widget body;
    if (_busy) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _writing
                ? (french ? 'Écriture des données' : 'Writing data')
                : (french
                      ? 'Vérification des clés (MCT étendu)'
                      : 'Checking keys (MCT extended)'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            french
                ? 'Maintenez la carte contre le lecteur.'
                : 'Keep the card against the reader.',
            style: const TextStyle(color: Nlc.slate400, fontSize: 12),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: _progress, minHeight: 8),
          ),
          if (_progress != null) ...[
            const SizedBox(height: 6),
            Text(
              '${(_progress! * 100).round()} %',
              style: const TextStyle(color: Nlc.slate400, fontSize: 12),
            ),
          ],
        ],
      );
    } else if (_done) {
      final failed = _failedBlocks > 0;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
                color: failed ? Nlc.amber400 : Nlc.emerald400,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failed
                      ? (french ? 'Écriture incomplète' : 'Write incomplete')
                      : (french ? 'Carte écrite' : 'Card written'),
                  style: TextStyle(
                    color: failed ? Nlc.amber300 : Nlc.emerald300,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            french
                ? '$_okBlocks bloc(s) écrit(s)'
                      '${failed ? ', $_failedBlocks en échec' : ''}'
                : '$_okBlocks block(s) written'
                      '${failed ? ', $_failedBlocks failed' : ''}',
            style: const TextStyle(color: Nlc.slate200, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _write(appState, l),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l.write_again),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: Text(
              french ? 'Choisir un autre badge' : 'Choose another badge',
            ),
          ),
        ],
      );
    } else if (cards.isEmpty) {
      body = Text(
        l.basic_write_no_dumps,
        style: const TextStyle(color: Nlc.slate400, fontSize: 13),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('simple-write-${_card?.id ?? 'none'}'),
            initialValue: _card?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l.select_saved_card,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final c in cards)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(c.name.isEmpty ? c.uid : c.name),
                ),
            ],
            onChanged: (value) => setState(() {
              _card = cards.firstWhere(
                (c) => c.id == value,
                orElse: () => cards.first,
              );
              _status = null;
            }),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _card == null ? null : () => _write(appState, l),
            icon: const Icon(Icons.save_alt, size: 18),
            label: Text(l.write),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: const TextStyle(color: Nlc.rose300, fontSize: 12),
            ),
          ],
        ],
      );
    }

    return NlcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NlcSectionTitle(
            l.write_card,
            icon: Icons.edit_rounded,
            color: Nlc.violet200,
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: theme.useMaterial3 ? 8 : 4),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}
