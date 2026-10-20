import 'package:nlc_toolkit/gui/component/mifare/classic.dart';
import 'package:nlc_toolkit/gui/component/error_message.dart';
import 'package:nlc_toolkit/gui/component/mifare/ultralight.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/recovery.dart';
import 'package:nlc_toolkit/helpers/mifare_ultralight/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'dart:async';

// Localizations
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';

enum MifareClassicState {
  none,
  checkKeys,
  checkKeysOngoing,
  recovery,
  recoveryOngoing,
  dump,
  dumpOngoing,
  save,
}

// cardExist true because we don't show error to user if nothing is done
class HFCardInfo {
  String uid;
  String sak;
  String atqa;
  String tech;
  String ats;
  TagType type;
  bool cardExist;

  HFCardInfo({
    this.uid = '',
    this.sak = '',
    this.atqa = '',
    this.tech = '',
    this.ats = '',
    this.type = TagType.unknown,
    this.cardExist = true,
  });
}

class LFCardInfo {
  LFCard? card;
  bool cardExist;

  LFCardInfo({this.cardExist = true});
}

class MifareClassicInfo {
  bool isEV1;
  MifareClassicRecovery? recovery;
  MifareClassicType type;
  MifareClassicState state;
  NTLevel? ntLevel;
  bool? hasBackdoor;

  MifareClassicInfo({
    MifareClassicRecovery? recovery,
    this.isEV1 = false,
    this.type = MifareClassicType.none,
    this.state = MifareClassicState.none,
    NTLevel? ntLevel,
    bool? hasBackdoor,
  });
}

class MifareUltralightInfo {
  Uint8List? version;
  Uint8List? signature;

  MifareUltralightInfo();
}

class ReadCardPage extends StatefulWidget {
  const ReadCardPage({super.key});

  @override
  ReadCardPageState createState() => ReadCardPageState();
}

class ReadCardPageState extends State<ReadCardPage> {
  String dumpName = "";
  HFCardInfo hfInfo = HFCardInfo();
  LFCardInfo lfInfo = LFCardInfo();
  MifareClassicInfo mfcInfo = MifareClassicInfo();
  MifareUltralightInfo mfuInfo = MifareUltralightInfo();

  bool isContinuousHFScan = false;
  bool isContinuousLFScan = false;
  bool scanInProgress = false;
  Timer? hfScanTimer;
  Timer? lfScanTimer;

  void updateMifareClassicRecovery() {
    setState(() {
      mfcInfo.recovery = mfcInfo.recovery;
    });
  }

  void updateMifareClassicInfo() {
    setState(() {
      mfcInfo = mfcInfo;
    });
  }

  Future<void> readLFInfo() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    setState(() {
      lfInfo = LFCardInfo();
    });

    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    LFCard? card = await appState.communicator!.readEM410X();
    card ??= await appState.communicator!.readHIDProx();
    card ??= await appState.communicator!.readViking();
    card ??= await appState.communicator!.readPac();
    card ??= await appState.communicator!.readIoProx();

    if (!mounted) return;
    if (card != null) {
      setState(() {
        lfInfo.card = card;
        scanInProgress = false;
      });
    } else {
      setState(() {
        lfInfo.cardExist = false;
        scanInProgress = false;
      });
    }
  }

  Future<void> startContinuousHFScan() async {
    if (isContinuousHFScan) return;

    setState(() {
      isContinuousHFScan = true;
      hfInfo = HFCardInfo();
      mfcInfo = MifareClassicInfo();
      mfuInfo = MifareUltralightInfo();
    });

    const scanInterval = Duration(seconds: 2);
    const maxDuration = Duration(minutes: 1);

    DateTime startTime = DateTime.now();

    hfScanTimer = Timer.periodic(scanInterval, (timer) async {
      if (DateTime.now().difference(startTime) > maxDuration || !mounted) {
        stopContinuousHFScan();
        return;
      }

      var info = await readHFInfo(context, updateMifareClassicRecovery);
      if (!mounted || !isContinuousHFScan) return;
      setState(() {
        hfInfo = info.$1;
        mfcInfo = info.$2;
        mfuInfo = info.$3;
      });

      if (hfInfo.cardExist && hfInfo.uid.isNotEmpty) {
        stopContinuousHFScan();
      }
    });

    var info = await readHFInfo(context, updateMifareClassicRecovery);
    if (!mounted || !isContinuousHFScan) return;
    setState(() {
      hfInfo = info.$1;
      mfcInfo = info.$2;
      mfuInfo = info.$3;
    });

    if (hfInfo.cardExist && hfInfo.uid.isNotEmpty) {
      stopContinuousHFScan();
    }
  }

  void stopContinuousHFScan() {
    if (hfScanTimer != null) {
      hfScanTimer?.cancel();
      hfScanTimer = null;

      if (mounted) {
        setState(() {
          isContinuousHFScan = false;
        });
      }
    }
  }

  Future<void> startContinuousLFScan() async {
    if (isContinuousLFScan) return;

    setState(() {
      isContinuousLFScan = true;
      lfInfo = LFCardInfo();
    });

    const scanInterval = Duration(seconds: 2);
    const maxDuration = Duration(minutes: 1);

    DateTime startTime = DateTime.now();

    lfScanTimer = Timer.periodic(scanInterval, (timer) async {
      if (DateTime.now().difference(startTime) > maxDuration || !mounted) {
        stopContinuousLFScan();
        return;
      }

      await readLFInfo();
      if (!mounted || !isContinuousLFScan) return;

      if (lfInfo.cardExist && lfInfo.card != null) {
        stopContinuousLFScan();
      }
    });

    await readLFInfo();
    if (!mounted || !isContinuousLFScan) return;
    if (lfInfo.cardExist && lfInfo.card != null) {
      stopContinuousLFScan();
    }
  }

  void stopContinuousLFScan() {
    if (lfScanTimer != null) {
      lfScanTimer?.cancel();
      lfScanTimer = null;

      if (mounted) {
        setState(() {
          isContinuousLFScan = false;
        });
      }
    }
  }

  @override
  void dispose() {
    hfScanTimer?.cancel();
    lfScanTimer?.cancel();
    super.dispose();
  }

  Future<void> saveHFCard() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;

    var tags = appState.sharedPreferencesProvider.getCards();
    tags.add(
      CardSave(
        uid: hfInfo.uid,
        sak: hexToBytes(hfInfo.sak)[0],
        atqa: hexToBytes(hfInfo.atqa),
        name: dumpName,
        tag: hfInfo.type != TagType.unknown ? hfInfo.type : TagType.mifare1K,
        data: [],
        ats: (hfInfo.ats != localizations.no)
            ? hexToBytes(hfInfo.ats)
            : Uint8List(0),
        extraData: CardSaveExtra(
          ultralightSignature: mfuInfo.signature,
          ultralightVersion: mfuInfo.version,
          ultralightCounters: [],
        ),
      ),
    );

    appState.sharedPreferencesProvider.setCards(tags);
  }

  Future<void> saveLFCard() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    var tags = appState.sharedPreferencesProvider.getCards();
    tags.add(
      CardSave(
        uid: lfInfo.card.toString(),
        name: dumpName,
        tag: lfInfo.card!.type,
      ),
    );
    appState.sharedPreferencesProvider.setCards(tags);
  }

  bool _readHighFrequency = true;

  Future<void> _showUnsupportedDevice(AppLocalizations localizations) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.no_supported),
        content: Text(localizations.lite_no_read),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(localizations.ok),
          ),
        ],
      ),
    );
  }

  Future<bool> _canRead(
    ChameleonGUIState appState,
    AppLocalizations localizations,
  ) async {
    if (appState.connector?.device == ChameleonDevice.ultra) {
      return true;
    }
    if (appState.connector?.device == ChameleonDevice.lite) {
      await _showUnsupportedDevice(localizations);
    } else {
      appState.changesMade();
    }
    return false;
  }

  Future<void> _readSelectedCard(
    ChameleonGUIState appState,
    AppLocalizations localizations,
  ) async {
    if (!await _canRead(appState, localizations) || !mounted) return;
    setState(() {
      scanInProgress = true;
      if (_readHighFrequency) {
        hfInfo = HFCardInfo();
        mfcInfo = MifareClassicInfo();
        mfuInfo = MifareUltralightInfo();
      } else {
        lfInfo = LFCardInfo();
      }
    });
    try {
      if (_readHighFrequency) {
        final info = await readHFInfo(context, updateMifareClassicRecovery);
        if (!mounted) return;
        setState(() {
          hfInfo = info.$1;
          mfcInfo = info.$2;
          mfuInfo = info.$3;
        });
      } else {
        await readLFInfo();
      }
    } finally {
      if (mounted) setState(() => scanInProgress = false);
    }
  }

  Future<void> _toggleContinuousScan(
    ChameleonGUIState appState,
    AppLocalizations localizations,
  ) async {
    if (_readHighFrequency && isContinuousHFScan) {
      stopContinuousHFScan();
      return;
    }
    if (!_readHighFrequency && isContinuousLFScan) {
      stopContinuousLFScan();
      return;
    }
    if (!await _canRead(appState, localizations) || !mounted) return;
    if (_readHighFrequency) {
      await startContinuousHFScan();
    } else {
      await startContinuousLFScan();
    }
  }

  void _selectFrequency(bool highFrequency) {
    if (scanInProgress || _readHighFrequency == highFrequency) return;
    if (isContinuousHFScan) stopContinuousHFScan();
    if (isContinuousLFScan) stopContinuousLFScan();
    setState(() => _readHighFrequency = highFrequency);
  }

  Future<void> _showSaveDialog(
    bool highFrequency,
    AppLocalizations localizations,
  ) async {
    var name = dumpName;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.enter_name_of_card),
        content: TextField(autofocus: true, onChanged: (value) => name = value),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () async {
              dumpName = name;
              if (highFrequency) {
                await saveHFCard();
              } else {
                await saveLFCard();
              }
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(localizations.save),
          ),
        ],
      ),
    );
  }

  Future<void> _showCardTypeDialog(
    ChameleonGUIState appState,
    AppLocalizations localizations,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.override_card_type),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(localizations.override_card_type_description),
            const SizedBox(height: 16),
            DropdownButton<TagType>(
              isExpanded: true,
              value: hfInfo.type,
              items:
                  [
                    ...getTagTypesByFrequency(TagFrequency.hf),
                    TagType.unknown,
                  ].map((tagType) {
                    return DropdownMenuItem<TagType>(
                      value: tagType,
                      child: Text(chameleonTagToString(tagType, localizations)),
                    );
                  }).toList(),
              onChanged: (newValue) async {
                if (newValue == null) return;
                setState(() {
                  hfInfo.type = newValue;
                  hfInfo.tech = chameleonTagToString(newValue, localizations);
                });

                if (isMifareClassic(newValue)) {
                  final info = await performMifareClassicScan(
                    appState.communicator!,
                    mfcInfo,
                    context,
                    updateMifareClassicRecovery,
                    override: newValue,
                  );
                  if (mounted) setState(() => mfcInfo = info.$2);
                } else if (isMifareUltralight(newValue)) {
                  final info = await performMifareUltralightScan(
                    appState.communicator!,
                    mfuInfo,
                    override: newValue,
                  );
                  if (mounted) setState(() => mfuInfo = info.$2);
                }

                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(localizations.cancel),
          ),
        ],
      ),
    );
  }

  Widget _technicalRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(
    BuildContext context,
    ChameleonGUIState appState,
    AppLocalizations localizations,
    bool french,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highFrequency = _readHighFrequency;
    final identifier = highFrequency
        ? hfInfo.uid
        : lfInfo.card!.toViewableString();
    final type = highFrequency
        ? hfInfo.tech
        : chameleonTagToString(lfInfo.card!.type, localizations);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: colors.primary),
                  const SizedBox(width: 9),
                  Text(
                    french ? 'Carte détectée' : 'Card detected',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                type,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                localizations.uid.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 5),
              SelectableText(
                identifier,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _showSaveDialog(highFrequency, localizations),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(
                  highFrequency
                      ? localizations.save_only_uid
                      : localizations.save,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ReadPanel(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 7),
            title: Text(
              french ? 'Détails techniques' : 'Technical details',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            leading: Icon(Icons.data_object_rounded, color: colors.primary),
            children: [
              _technicalRow(context, localizations.uid, identifier),
              if (highFrequency) ...[
                _technicalRow(context, localizations.sak, hfInfo.sak),
                _technicalRow(context, localizations.atqa, hfInfo.atqa),
                _technicalRow(context, localizations.ats, hfInfo.ats),
                if (mfcInfo.ntLevel != null)
                  _technicalRow(
                    context,
                    localizations.prng_type,
                    mfClassicGetPrngType(mfcInfo.ntLevel!, localizations),
                  ),
                if (mfcInfo.hasBackdoor != null)
                  _technicalRow(
                    context,
                    localizations.has_backdoor_support,
                    mfcInfo.hasBackdoor! ? localizations.yes : localizations.no,
                  ),
              ],
              _technicalRow(context, localizations.card_tech, type),
            ],
          ),
        ),
        if (highFrequency) ...[
          const SizedBox(height: 14),
          _ReadPanel(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              maintainState: true,
              title: Text(
                french ? 'Fonctions avancées' : 'Advanced functions',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                french
                    ? 'Type de carte, clés et données'
                    : 'Card type, keys and data',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              leading: Icon(Icons.tune_rounded, color: colors.primary),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        _showCardTypeDialog(appState, localizations),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(localizations.override_card_type),
                  ),
                ),
                if (isMifareClassic(hfInfo.type))
                  MifareClassicHelper(mfcInfo: mfcInfo, hfInfo: hfInfo),
                if (isMifareUltralight(hfInfo.type))
                  MifareUltralightHelper(hfInfo: hfInfo),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.watch<ChameleonGUIState>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final french = Localizations.localeOf(context).languageCode == 'fr';
    final continuous = _readHighFrequency
        ? isContinuousHFScan
        : isContinuousLFScan;
    final busy = scanInProgress || continuous;
    final found = _readHighFrequency
        ? hfInfo.uid.isNotEmpty
        : lfInfo.card != null;
    final noCard = _readHighFrequency ? !hfInfo.cardExist : !lfInfo.cardExist;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 32, 22, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'NLC TOOLKIT  /  ${french ? 'LECTURE' : 'READ'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    localizations.read_card,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    french
                        ? 'Choisissez une fréquence, puis placez la carte contre le ChameleonUltra V2.'
                        : 'Choose a frequency, then place the card against the ChameleonUltra V2.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    french ? 'Fréquence' : 'Frequency',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _FrequencyChoice(
                          selected: _readHighFrequency,
                          label: 'HF',
                          subtitle: '13,56 MHz',
                          icon: Icons.nfc_rounded,
                          onTap: scanInProgress
                              ? null
                              : () => _selectFrequency(true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FrequencyChoice(
                          selected: !_readHighFrequency,
                          label: 'LF',
                          subtitle: '125 kHz',
                          icon: Icons.sensors_rounded,
                          onTap: scanInProgress
                              ? null
                              : () => _selectFrequency(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ReadPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 45,
                              height: 45,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                Icons.radar_rounded,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    busy
                                        ? (french
                                              ? 'Recherche en cours'
                                              : 'Scanning')
                                        : (french
                                              ? 'Prêt à lire'
                                              : 'Ready to read'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: colors.onSurface,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    busy
                                        ? (french
                                              ? 'Maintenez la carte à proximité de l’appareil.'
                                              : 'Keep the card close to the device.')
                                        : (french
                                              ? 'Lancez une lecture lorsque la carte est en place.'
                                              : 'Start reading when the card is in place.'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (busy) ...[
                          const SizedBox(height: 20),
                          const LinearProgressIndicator(),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () =>
                                    _readSelectedCard(appState, localizations),
                          icon: const Icon(Icons.contactless_rounded),
                          label: Text(localizations.read),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: scanInProgress
                              ? null
                              : () => _toggleContinuousScan(
                                  appState,
                                  localizations,
                                ),
                          icon: Icon(
                            continuous
                                ? Icons.stop_rounded
                                : Icons.autorenew_rounded,
                          ),
                          label: Text(
                            continuous
                                ? localizations.cancel
                                : localizations.continuous_scan,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (found)
                    _buildResult(context, appState, localizations, french)
                  else if (noCard && !busy)
                    ErrorMessage(errorMessage: localizations.no_card_found)
                  else if (!busy)
                    Text(
                      french
                          ? 'Le résultat apparaîtra ici après la lecture.'
                          : 'The result will appear here after reading.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadPanel extends StatelessWidget {
  const _ReadPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: child,
    );
  }
}

class _FrequencyChoice extends StatelessWidget {
  const _FrequencyChoice({
    required this.selected,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: selected ? colors.primary.withValues(alpha: 0.11) : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          child: Row(
            children: [
              Icon(
                icon,
                size: 23,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: colors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
