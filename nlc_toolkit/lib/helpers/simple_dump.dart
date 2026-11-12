// Lecture guidée complète d'un badge HF, réutilisable : détection, vérification des clés avec
// le dictionnaire MCT étendu, récupération des clés manquantes et extraction du dump. Renvoie la
// carte reconstruite (ou null si aucune carte). Utilisé par la carte « Lire » du mode simple et
// par « Lire le tag » depuis un immeuble.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';

/// Étapes visibles pendant une lecture guidée.
enum SimpleDumpStep { reading, keys, recover, extract }

/// Lit un badge HF en entier. [onStep] reçoit chaque étape pour l'affichage. Renvoie `null`
/// si aucune carte n'a été détectée. En cas de MIFARE Classic, les clés sont cherchées avec le
/// dictionnaire MCT étendu (repli : MCT standard) et le dump est extrait.
Future<CardSave?> readSimpleDump(
  BuildContext context,
  NlcAppState appState,
  AppLocalizations l, {
  void Function(SimpleDumpStep step)? onStep,
}) async {
  onStep?.call(SimpleDumpStep.reading);
  final info = await readHFInfo(context, () {});
  final hfInfo = info.$1;
  final mfcInfo = info.$2;
  final mfuInfo = info.$3;

  final recovery = mfcInfo.recovery;
  if (isMifareClassic(hfInfo.type) && recovery != null) {
    final dicts = appState.sharedPreferencesProvider.getDictionaries(
      keyLength: 12,
    );
    recovery.dictionaries = dicts;
    recovery.selectedDictionary = dicts.firstWhere(
      (d) => d.id == 'mct-extended-std',
      orElse: () => dicts.firstWhere(
        (d) => d.id == 'mct-std',
        orElse: () =>
            dicts.isEmpty ? Dictionary(id: '', name: '', keys: []) : dicts.first,
      ),
    );

    onStep?.call(SimpleDumpStep.keys);
    try {
      await recovery.checkKeys();
    } catch (e) {
      appState.log?.e(e.toString());
    }
    if (!recovery.allKeysExists) {
      onStep?.call(SimpleDumpStep.recover);
      try {
        await recovery.recoverKeys();
      } catch (e) {
        appState.log?.e(e.toString());
      }
    }
    onStep?.call(SimpleDumpStep.extract);
    try {
      await recovery.dumpData();
    } catch (e) {
      appState.log?.e(e.toString());
    }
  }

  if (hfInfo.uid.isEmpty) return null; // Aucune carte lue.

  return CardSave(
    uid: hfInfo.uid,
    sak: hfInfo.sak.isEmpty ? 0 : hexToBytes(hfInfo.sak)[0],
    atqa: hfInfo.atqa.isEmpty ? Uint8List(0) : hexToBytes(hfInfo.atqa),
    name: hfInfo.uid.replaceAll(' ', ''),
    tag: mfcInfo.type != MifareClassicType.none
        ? mfClassicGetChameleonTagType(mfcInfo.type)
        : (hfInfo.type != TagType.unknown ? hfInfo.type : TagType.mifare1K),
    data: mfcInfo.recovery?.cardData ?? const [],
    ats: (hfInfo.ats != l.no && hfInfo.ats.isNotEmpty)
        ? hexToBytes(hfInfo.ats)
        : Uint8List(0),
    extraData: CardSaveExtra(
      ultralightSignature: mfuInfo.signature,
      ultralightVersion: mfuInfo.version,
      ultralightCounters: [],
    ),
  );
}

/// Libellé d'étape localisé pour une barre de progression.
String simpleDumpStepLabel(SimpleDumpStep step, AppLocalizations l) =>
    switch (step) {
      SimpleDumpStep.reading => l.nlc_step_reading,
      SimpleDumpStep.keys => l.nlc_step_keys,
      SimpleDumpStep.recover => l.nlc_step_recover,
      SimpleDumpStep.extract => l.nlc_step_extract,
    };
