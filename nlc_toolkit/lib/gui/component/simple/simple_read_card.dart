// Carte « Lire » du mode simplifié : lecture guidée en un bouton, affichée
// directement sur l'accueil (ou dans la page de lecture simple). Lit le badge,
// vérifie les clés avec le dictionnaire MCT étendu, récupère les clés manquantes,
// extrait le dump, puis propose de l'enregistrer. L'utilisateur ne voit qu'une
// barre de progression avec l'étape en cours.
import 'package:flutter/material.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/gui/menu/pages/dump_editor.dart';
import 'package:nlc_toolkit/gui/page/badge_dumps_ui.dart';
import 'package:nlc_toolkit/gui/page/read_card.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:provider/provider.dart';

import 'dart:typed_data';

class SimpleReadCard extends StatefulWidget {
  const SimpleReadCard({super.key});

  @override
  State<SimpleReadCard> createState() => _SimpleReadCardState();
}

class _SimpleReadCardState extends State<SimpleReadCard> {
  String _dumpName = "";
  HFCardInfo _hfInfo = HFCardInfo();
  MifareClassicInfo _mfcInfo = MifareClassicInfo();
  MifareUltralightInfo _mfuInfo = MifareUltralightInfo();
  bool _scanInProgress = false;

  void _updateRecovery() {
    if (mounted) setState(() => _mfcInfo.recovery = _mfcInfo.recovery);
  }

  Future<bool> _canRead(NlcAppState appState, AppLocalizations l) async {
    if (appState.connector?.device == ChameleonDevice.ultra) return true;
    if (appState.connector?.device == ChameleonDevice.lite) {
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
      appState.changesMade();
    }
    return false;
  }

  Future<void> _read(NlcAppState appState, AppLocalizations l) async {
    if (!await _canRead(appState, l) || !mounted) return;
    setState(() {
      _scanInProgress = true;
      _hfInfo = HFCardInfo();
      _mfcInfo = MifareClassicInfo();
      _mfuInfo = MifareUltralightInfo();
      _dumpName = "";
    });
    try {
      final info = await readHFInfo(context, _updateRecovery);
      if (!mounted) return;
      setState(() {
        _hfInfo = info.$1;
        _mfcInfo = info.$2;
        _mfuInfo = info.$3;
      });
      final recovery = _mfcInfo.recovery;
      if (isMifareClassic(_hfInfo.type) && recovery != null) {
        // Dictionnaire MCT étendu, choisi automatiquement (repli : MCT standard).
        final dicts = appState.sharedPreferencesProvider.getDictionaries(
          keyLength: 12,
        );
        recovery.dictionaries = dicts;
        recovery.selectedDictionary = dicts.firstWhere(
          (d) => d.id == 'mct-extended-std',
          orElse: () => dicts.firstWhere(
            (d) => d.id == 'mct-std',
            orElse: () => dicts.isEmpty
                ? Dictionary(id: '', name: '', keys: [])
                : dicts.first,
          ),
        );

        setState(() => _mfcInfo.state = MifareClassicState.checkKeysOngoing);
        try {
          await recovery.checkKeys();
        } catch (e) {
          appState.log?.e(e.toString());
        }
        if (!mounted) return;
        if (!recovery.allKeysExists) {
          setState(() => _mfcInfo.state = MifareClassicState.recoveryOngoing);
          try {
            await recovery.recoverKeys();
          } catch (e) {
            appState.log?.e(e.toString());
          }
          if (!mounted) return;
        }
        setState(() => _mfcInfo.state = MifareClassicState.dumpOngoing);
        try {
          await recovery.dumpData();
        } catch (e) {
          appState.log?.e(e.toString());
        }
        if (!mounted) return;
        setState(() => _mfcInfo.state = MifareClassicState.save);
      }
    } catch (e) {
      appState.log?.e(e.toString());
    } finally {
      if (mounted) setState(() => _scanInProgress = false);
    }
  }

  CardSave _dumpCard(AppLocalizations l) => CardSave(
    uid: _hfInfo.uid,
    sak: _hfInfo.sak.isEmpty ? 0 : hexToBytes(_hfInfo.sak)[0],
    atqa: _hfInfo.atqa.isEmpty ? Uint8List(0) : hexToBytes(_hfInfo.atqa),
    name: _dumpName.isEmpty ? _hfInfo.uid.replaceAll(' ', '') : _dumpName,
    tag: _mfcInfo.type != MifareClassicType.none
        ? mfClassicGetChameleonTagType(_mfcInfo.type)
        : (_hfInfo.type != TagType.unknown ? _hfInfo.type : TagType.mifare1K),
    data: _mfcInfo.recovery?.cardData ?? const [],
    ats: (_hfInfo.ats != l.no && _hfInfo.ats.isNotEmpty)
        ? hexToBytes(_hfInfo.ats)
        : Uint8List(0),
    extraData: CardSaveExtra(
      ultralightSignature: _mfuInfo.signature,
      ultralightVersion: _mfuInfo.version,
      ultralightCounters: [],
    ),
  );

  Future<void> _viewDump(AppLocalizations l) async {
    final card = _dumpCard(l);
    await showDialog<void>(
      context: context,
      builder: (_) => DumpEditor(
        cardSave: card,
        onSave: (data) => _mfcInfo.recovery?.cardData = data,
      ),
    );
  }

  Future<void> _saveToLibrary(AppLocalizations l) async {
    final appState = context.read<NlcAppState>();
    final tags = appState.sharedPreferencesProvider.getCards();
    tags.add(_dumpCard(l));
    appState.sharedPreferencesProvider.setCards(tags);
    appState.changesMade();
    if (mounted) showNlcToast(context, l.nlc_saved_to_library);
  }

  void _reset() {
    setState(() {
      _hfInfo = HFCardInfo();
      _mfcInfo = MifareClassicInfo();
      _mfuInfo = MifareUltralightInfo();
      _dumpName = "";
    });
  }

  String _stepTitle(AppLocalizations l) => switch (_mfcInfo.state) {
    MifareClassicState.checkKeysOngoing => l.nlc_step_keys,
    MifareClassicState.recoveryOngoing => l.nlc_step_recover,
    MifareClassicState.dumpOngoing => l.nlc_step_extract,
    _ => l.nlc_step_reading,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final appState = context.watch<NlcAppState>();
    final french = Localizations.localeOf(context).languageCode == 'fr';

    final processing =
        _scanInProgress ||
        const [
          MifareClassicState.checkKeysOngoing,
          MifareClassicState.recoveryOngoing,
          MifareClassicState.dumpOngoing,
        ].contains(_mfcInfo.state);
    final done =
        !processing &&
        (_mfcInfo.state == MifareClassicState.save || _hfInfo.uid.isNotEmpty);
    final noCard = !processing && !done && !_hfInfo.cardExist;

    Widget body;
    if (processing) {
      final recovery = _mfcInfo.recovery;
      final value =
          (_mfcInfo.state == MifareClassicState.dumpOngoing &&
              recovery != null &&
              recovery.dumpProgress > 0)
          ? recovery.dumpProgress
          : null;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _stepTitle(l),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (recovery != null && recovery.state.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              recovery.state,
              style: const TextStyle(color: Nlc.slate400, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: value, minHeight: 8),
          ),
          if (value != null) ...[
            const SizedBox(height: 6),
            Text(
              '${(value * 100).round()} %',
              style: const TextStyle(color: Nlc.slate400, fontSize: 12),
            ),
          ],
        ],
      );
    } else if (done) {
      final canSaveToSite = context.read<ErpServices>().badgeDumps.available;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Nlc.emerald400,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.nlc_simple_card_ready,
                  style: const TextStyle(
                    color: Nlc.emerald300,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _hfInfo.tech.isEmpty
                ? chameleonTagToString(_hfInfo.type, l)
                : _hfInfo.tech,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            _hfInfo.uid,
            style: const TextStyle(
              color: Nlc.slate200,
              fontSize: 14,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (_mfcInfo.type != MifareClassicType.none) ...[
            FilledButton.icon(
              onPressed: () => _viewDump(l),
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: Text(l.view_dump),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => _saveToLibrary(l),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(l.save),
          ),
          if (canSaveToSite) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => saveCardToSite(context, _dumpCard(l)),
              icon: const Icon(Icons.apartment_rounded, size: 18),
              label: Text(l.nlc_save_to_site),
            ),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l.read),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            french
                ? 'Placez la carte contre le lecteur, puis lancez la lecture.'
                : 'Place the card against the reader, then start reading.',
            style: const TextStyle(color: Nlc.slate400, fontSize: 12),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _read(appState, l),
            icon: const Icon(Icons.contactless_rounded, size: 18),
            label: Text(l.read),
          ),
          if (noCard) ...[
            const SizedBox(height: 12),
            Text(
              l.no_card_found,
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
            l.read_card,
            icon: Icons.nfc_rounded,
            color: Nlc.emerald300,
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}
