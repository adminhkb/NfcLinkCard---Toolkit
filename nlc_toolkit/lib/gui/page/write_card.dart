import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/gui/component/card_list.dart';
import 'package:nlc_toolkit/gui/component/error_message.dart';
import 'package:nlc_toolkit/gui/component/mifare/mct_write_panel.dart';
import 'package:nlc_toolkit/gui/component/mifare/vanity_sak_checkbox.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/mct_write.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/mct_write_runner.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/vanity_sak.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/write/base.dart';
import 'package:nlc_toolkit/helpers/write.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';

class WriteCardPage extends StatefulWidget {
  const WriteCardPage({super.key, this.initialCard});

  /// Carte à écrire fournie d'avance (copie d'un dump rattaché à un immeuble) : la page saute
  /// le choix dans la bibliothèque et démarre à la détection de la carte magique.
  final CardSave? initialCard;

  @override
  WriteCardPageState createState() => WriteCardPageState();
}

class WriteCardPageState extends State<WriteCardPage> {
  int step = 0;
  int progress = -1;
  bool written = false;
  bool vanitySak = false;
  bool showVanitySak = false;
  CardSave? card;
  AbstractWriteHelper? baseHelper;
  AbstractWriteHelper? helper;

  // ─── Mode simple : clonage guidé en un bouton ───
  bool _simpleBusy = false;
  double? _simpleProgress;
  String? _simpleStatus;
  bool _simpleDone = false;
  bool _simpleWriting = false; // false = vérification des clés, true = écriture
  int _simpleOkBlocks = 0;
  int _simpleFailedBlocks = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialCard != null) {
      card = widget.initialCard;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialCard());
    }
  }

  /// Prépare la page avec la carte fournie, comme une sélection dans la bibliothèque.
  Future<void> _loadInitialCard() async {
    final selectedCard = widget.initialCard!;
    final appState = context.read<NlcAppState>();
    final localizations = AppLocalizations.of(context)!;
    // En mode simple, la carte fournie est seulement pré-sélectionnée comme source :
    // pas de préparation du lecteur ni d'étapes avancées.
    if (!appState.advancedMode) {
      setState(() => card = selectedCard);
      return;
    }
    setState(() {
      card = selectedCard;
      showVanitySak = mfClassicVanitySakVisibleInWrite(
        selectedCard.tag,
        selectedCard.data,
      );
      vanitySak = mfClassicVanitySakFromUidHex(selectedCard.uid) ?? false;
      baseHelper = AbstractWriteHelper.getClassByCardType(
        selectedCard.tag,
        appState,
        updateState,
        localizations,
      );
      if (baseHelper != null) helper = baseHelper!.getAvailableMethods()[0];
      // Les étapes 0 (choix de la carte) sont déjà faites : on passe au choix de la méthode.
      step = 1;
    });
    await helper?.getCardType();
    if (mounted) setState(() {});
  }

  Future<String?> cardSelectDialog(BuildContext context) {
    var appState = context.read<NlcAppState>();
    var tags = appState.sharedPreferencesProvider.getCards();

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(cards: tags, onTap: onTap),
    );
  }

  Future<void> onTap(
    CardSave selectedCard,
    dynamic close,
    AppLocalizations localizations,
  ) async {
    var appState = Provider.of<NlcAppState>(context, listen: false);

    setState(() {
      card = selectedCard;
      showVanitySak = mfClassicVanitySakVisibleInWrite(
        selectedCard.tag,
        selectedCard.data,
      );
      vanitySak = mfClassicVanitySakFromUidHex(selectedCard.uid) ?? false;
      baseHelper = AbstractWriteHelper.getClassByCardType(
        selectedCard.tag,
        appState,
        updateState,
        localizations,
      );
    });

    if (baseHelper != null) {
      setState(() {
        helper = baseHelper!.getAvailableMethods()[0];
      });
    }

    await helper?.getCardType();

    if (!mounted) return;
    close(context, selectedCard.name);
  }

  Future<void> detectMagicType() async {
    var appState = Provider.of<NlcAppState>(context, listen: false);
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    var localizations = AppLocalizations.of(context)!;

    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    for (final magicHelper in baseHelper!.getAvailableMethods()) {
      if (await magicHelper.isMagic(card)) {
        setState(() {
          helper = magicHelper;
        });

        try {
          await helper?.getCardType();
        } catch (_) {
          await helper?.getCardType();
        }

        appState.log!.i("Detected Magic card type: ${magicHelper.name}");
        scaffoldMessenger.hideCurrentSnackBar();
        var snackBar = SnackBar(
          content: Text(
            '${localizations.detected_magic_card_type}: ${helper!.name}',
          ),
          action: SnackBarAction(label: localizations.close, onPressed: () {}),
        );

        scaffoldMessenger.showSnackBar(snackBar);
        return;
      }
    }

    var snackBar = SnackBar(
      content: Text(localizations.failed_to_detect_magic_card_type),
      action: SnackBarAction(label: localizations.close, onPressed: () {}),
    );

    scaffoldMessenger.showSnackBar(snackBar);
  }

  void updateState() {
    setState(() {
      helper = helper;
    });
  }

  void updateProgress(int writeProgress) {
    setState(() {
      progress = writeProgress;
    });
  }

  Future<void> writeCard() async {
    var appState = Provider.of<NlcAppState>(context, listen: false);
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    var localizations = AppLocalizations.of(context)!;
    SnackBar snackBar;
    updateProgress(0);

    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    if (helper is BaseMifareClassicWriteHelper) {
      (helper as BaseMifareClassicWriteHelper).vanitySak = vanitySak;
    }
    if (await helper!.writeData(card!, updateProgress)) {
      snackBar = SnackBar(
        content: Text(localizations.magic_success_write),
        action: SnackBarAction(label: localizations.close, onPressed: () {}),
      );
    } else {
      snackBar = SnackBar(
        content: Text(localizations.magic_failed_write),
        action: SnackBarAction(label: localizations.close, onPressed: () {}),
      );
    }

    scaffoldMessenger.hideCurrentSnackBar();
    scaffoldMessenger.showSnackBar(snackBar);

    setState(() {
      written = true;
    });

    updateProgress(-1);
  }

  void onStepContinue() async {
    var localizations = AppLocalizations.of(context)!;
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    var appState = Provider.of<NlcAppState>(context, listen: false);

    if (appState.connector!.device == ChameleonDevice.lite) {
      showDialog<String>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(localizations.no_supported),
          content: Text(
            localizations.lite_no_read,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, localizations.ok),
              child: Text(localizations.ok),
            ),
          ],
        ),
      );

      return;
    }

    if (step != 2) {
      if (step == 1) {
        await helper?.reset();
      }
      setState(() {
        step++;
      });
    } else if (helper != null && helper!.isReady() && progress == -1) {
      SnackBar snackBar;
      updateProgress(0);

      if (!await helper!.isCompatible(card!)) {
        snackBar = SnackBar(
          content: Text(localizations.magic_incompatible_card),
          action: SnackBarAction(
            label: localizations.continue_anyway,
            onPressed: () async {
              await writeCard();
            },
          ),
        );

        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(snackBar);
      } else {
        await writeCard();
      }

      updateProgress(-1);
    }
  }

  void onStepBack() async {
    setState(() {
      written = false;
      step--;
    });

    if (step == 1) {
      await helper?.reset();
    }
  }

  void onStepReset() async {
    setState(() {
      written = false;
      step = 0;
    });
  }

  List<Widget> createButtonsForStep(ControlsDetails details, int step) {
    var localizations = AppLocalizations.of(context)!;
    List<Widget> widgets = [];

    if (written) {
      widgets.add(
        TextButton(
          onPressed: (progress == -1) ? onStepContinue : null,
          child: Text(localizations.write_again),
        ),
      );

      widgets.add(
        TextButton(
          onPressed: (progress == -1) ? onStepReset : null,
          child: Text(localizations.reset),
        ),
      );
    } else {
      if (step == 0 || step == 1) {
        widgets.add(
          TextButton(
            onPressed:
                (step == 0 && card == null || step == 1 && baseHelper == null)
                ? null
                : onStepContinue,
            child: Text(localizations.next),
          ),
        );
      }

      if (step == 2) {
        widgets.add(
          TextButton(
            onPressed: (helper != null && helper!.isReady() && progress == -1)
                ? onStepContinue
                : null,
            child: Text(localizations.write_data_to_magic_card),
          ),
        );
      }

      if (step != 0) {
        widgets.add(
          TextButton(onPressed: onStepBack, child: Text(localizations.back)),
        );
      }
    }

    return widgets;
  }

  /* ─────────────── Mode simple : clonage guidé en un bouton ─────────────── */

  /// Les cartes MIFARE Classic enregistrées, utilisables comme source du clonage.
  List<CardSave> get _savedMfcCards =>
      context
          .read<NlcAppState>()
          .sharedPreferencesProvider
          .getCards()
          .where((c) => isMifareClassic(c.tag))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Clone le dump sélectionné sur la carte cible sans aucune configuration :
  /// vérification des clés avec le dictionnaire MCT étendu, puis écriture de tous
  /// les secteurs (trailers et bloc constructeur compris, comme une carte magique
  /// Gen2 générique). L'utilisateur ne voit qu'une barre de progression.
  Future<void> _writeSimple(
    NlcAppState appState,
    AppLocalizations localizations,
  ) async {
    final source = card;
    if (source == null) return;

    final connector = appState.connector;
    if (connector == null ||
        !connector.connected ||
        connector.device != ChameleonDevice.ultra) {
      if (connector?.device == ChameleonDevice.lite) {
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
      } else {
        setState(() => _simpleStatus = localizations.basic_write_connect_ultra);
      }
      return;
    }

    final communicator = appState.communicator!;
    final chunkSize =
        connector.connectionType == ConnectionType.ble ? 32 : 64;

    setState(() {
      _simpleBusy = true;
      _simpleDone = false;
      _simpleStatus = null;
      _simpleProgress = 0;
      _simpleWriting = false;
    });

    try {
      // 1. Vérification du dictionnaire MCT étendu (repli : MCT standard), choisi
      //    automatiquement, pour reconstituer les clés de la carte cible.
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

      // 2. Carte des clés : on teste les clés sur la carte cible.
      final keyMap = await mctMapKeys(
        communicator,
        candidates,
        chunkSize: chunkSize,
        onProgress: (p) {
          if (mounted) setState(() => _simpleProgress = p);
        },
      );
      if (!mounted) return;
      if (keyMap == null) {
        setState(() => _simpleStatus = localizations.not_mifare_classic_card);
        return;
      }

      // 3. Plan d'écriture du dump complet : tous les secteurs porteurs de données,
      //    trailers activés, écriture du bloc constructeur (bloc 0) autorisée.
      setState(() {
        _simpleWriting = true;
        _simpleProgress = 0;
      });
      var plan = buildMctDumpWritePlan(
        source,
        MctWriteOptions(
          sectors: mctSectorsWithData(source).toSet(),
          writeManufacturerBlock: true,
          writeTrailers: true,
        ),
      );
      // Si le bloc 0 du dump ne peut pas être écrit tel quel (BCC invalide), on
      // clone quand même le reste de la carte.
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
        setState(() => _simpleStatus = localizations.mct_nothing_to_write);
        return;
      }

      // 4. Écriture des données.
      final report = await mctRunWritePlan(
        communicator,
        plan,
        keyMap,
        onProgress: (p) {
          if (mounted) setState(() => _simpleProgress = p);
        },
      );
      if (!mounted) return;
      if (report.cardChanged) {
        setState(() => _simpleStatus = localizations.mct_card_changed);
        return;
      }
      setState(() {
        _simpleOkBlocks =
            report.count(MctBlockOutcome.verified) +
            report.count(MctBlockOutcome.written);
        _simpleFailedBlocks =
            report.count(MctBlockOutcome.failed) +
            report.count(MctBlockOutcome.noKey);
        _simpleDone = true;
      });
      appState.changesMade();
    } catch (_) {
      if (mounted) setState(() => _simpleStatus = localizations.mct_write_error);
    } finally {
      if (mounted) {
        setState(() {
          _simpleBusy = false;
          _simpleProgress = null;
        });
      }
    }
  }

  /// Page ouverte par-dessus une autre (bouton « Copier » d'un immeuble) et non depuis le menu :
  /// il n'y a alors ni menu latéral ni fond, il faut un bouton pour revenir.
  bool get _openedAsRoute => widget.initialCard != null;

  Widget _backButton(AppLocalizations localizations) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(localizations.back),
        ),
      ),
    );
  }

  void _simpleReset() {
    setState(() {
      _simpleDone = false;
      _simpleStatus = null;
      _simpleOkBlocks = 0;
      _simpleFailedBlocks = 0;
    });
  }

  Widget _buildSimple(
    BuildContext context,
    NlcAppState appState,
    AppLocalizations localizations,
    ThemeData theme,
    ColorScheme colors,
    bool french,
  ) {
    // Le badge reçu de l'ERP (bouton « Copier ») n'est pas rangé dans la bibliothèque locale :
    // on l'ajoute à la liste, sinon la page affichait « Aucun dump » alors qu'il est prêt.
    final initial = widget.initialCard;
    final cards = [
      ?initial,
      ..._savedMfcCards.where((c) => c.id != initial?.id),
    ];

    Widget panel;
    if (_simpleBusy) {
      panel = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _simpleWriting
                ? (french ? 'Écriture des données' : 'Writing data')
                : (french
                      ? 'Vérification des clés (MCT étendu)'
                      : 'Checking keys (MCT extended)'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            french
                ? 'Maintenez la carte contre le ChameleonUltra V2.'
                : 'Keep the card against the ChameleonUltra V2.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _simpleProgress,
              minHeight: 8,
            ),
          ),
          if (_simpleProgress != null) ...[
            const SizedBox(height: 8),
            Text(
              '${(_simpleProgress! * 100).round()} %',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    } else if (_simpleDone) {
      final failed = _simpleFailedBlocks > 0;
      panel = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
                color: failed ? colors.error : colors.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  failed
                      ? (french ? 'Écriture incomplète' : 'Write incomplete')
                      : (french ? 'Carte écrite' : 'Card written'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: failed ? colors.error : colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            french
                ? '$_simpleOkBlocks bloc(s) écrit(s)'
                      '${failed ? ', $_simpleFailedBlocks en échec' : ''}'
                : '$_simpleOkBlocks block(s) written'
                      '${failed ? ', $_simpleFailedBlocks failed' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _writeSimple(appState, localizations),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(localizations.write_again),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _simpleReset,
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(
              french ? 'Choisir un autre badge' : 'Choose another badge',
            ),
          ),
        ],
      );
    } else {
      panel = Column(
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
                child: Icon(Icons.edit_rounded, color: colors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  french ? 'Prêt à écrire' : 'Ready to write',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (cards.isEmpty)
            Text(
              localizations.basic_write_no_dumps,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              key: ValueKey('simple-write-${card?.id ?? 'none'}'),
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
              onChanged: (value) => setState(() {
                card = cards.firstWhere(
                  (c) => c.id == value,
                  orElse: () => cards.first,
                );
                _simpleStatus = null;
              }),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: card == null
                  ? null
                  : () => _writeSimple(appState, localizations),
              icon: const Icon(Icons.save_alt),
              label: Text(localizations.write),
            ),
          ],
          if (_simpleStatus != null) ...[
            const SizedBox(height: 14),
            ErrorMessage(errorMessage: _simpleStatus!),
          ],
        ],
      );
    }

    return Scaffold(
      backgroundColor: _openedAsRoute ? colors.surface : Colors.transparent,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 32, 22, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_openedAsRoute) _backButton(localizations),
                  NlcPageHeader(
                    eyebrow: 'NLC Toolkit',
                    eyebrowIcon: Icons.edit_rounded,
                    title: localizations.write_card,
                    subtitle: Text(
                      french
                          ? 'Choisissez un badge enregistré, puis placez la carte cible contre le ChameleonUltra V2.'
                          : 'Choose a saved badge, then place the target card against the ChameleonUltra V2.',
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SimpleWritePanel(child: panel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final appState = context.watch<NlcAppState>();
    final theme = Theme.of(context);
    final french = Localizations.localeOf(context).languageCode == 'fr';
    if (!appState.advancedMode) {
      return _buildSimple(
        context,
        appState,
        localizations,
        theme,
        theme.colorScheme,
        french,
      );
    }
    var typeLocalization = {
      'gen1': localizations.gen1,
      'gen2': localizations.gen2,
      'gen3': localizations.gen3,
      't55xx': localizations.t55xx,
    };

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: _openedAsRoute ? colorScheme.surface : Colors.transparent,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 32, 22, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_openedAsRoute) _backButton(localizations),
                  NlcPageHeader(
                    eyebrow: 'NLC Toolkit',
                    eyebrowIcon: Icons.edit_rounded,
                    title: localizations.basic_write_title,
                    subtitle: Text(localizations.basic_write_description),
                  ),
                  const SizedBox(height: 20),
                  const MctWritePanel(),
                  const SizedBox(height: 18),
                  Card(
                    child: ExpansionTile(
                      maintainState: true,
                      leading: Icon(
                        Icons.auto_awesome_outlined,
                        color: colorScheme.secondary,
                      ),
                      title: Text(localizations.magic_dump_writer),
                      subtitle: Text(
                        localizations.magic_dump_writer_description,
                      ),
                      children: [
                        Stepper(
                          physics: const ClampingScrollPhysics(),
                          controlsBuilder:
                              (BuildContext context, ControlsDetails details) {
                                return Column(
                                  children: [
                                    const SizedBox(height: 8),
                                    Row(
                                      children: createButtonsForStep(
                                        details,
                                        step,
                                      ),
                                    ),
                                  ],
                                );
                              },
                          currentStep: step,
                          steps: [
                            Step(
                              title: Text(
                                localizations.select_saved_card_to_write,
                              ),
                              subtitle: step > 0 && card != null
                                  ? Text(card!.name)
                                  : null,
                              content: Card(
                                child: Column(
                                  children: [
                                    ListTile(
                                      title: Row(
                                        children: [
                                          FilterChip(
                                            onSelected: (bool selected) {
                                              cardSelectDialog(context);
                                            },
                                            avatar: (card != null)
                                                ? CircleAvatar(
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    child: Icon(
                                                      (chameleonTagToFrequency(
                                                                card!.tag,
                                                              ) ==
                                                              TagFrequency.hf)
                                                          ? Icons.credit_card
                                                          : Icons.wifi,
                                                      color: card!.color,
                                                    ),
                                                  )
                                                : null,
                                            label: Text(
                                              (card != null)
                                                  ? card!.name
                                                  : localizations
                                                        .select_saved_card,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (showVanitySak)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          12,
                                        ),
                                        child: VanitySakCheckbox(
                                          value: vanitySak,
                                          onChanged: (v) =>
                                              setState(() => vanitySak = v!),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              isActive: step >= 1,
                            ),
                            Step(
                              title: Text(localizations.select_magic_card),
                              subtitle: step > 1 && helper != null
                                  ? Text(typeLocalization[helper!.name]!)
                                  : null,
                              content: Card(
                                child: ListTile(
                                  title: (baseHelper != null)
                                      ? Wrap(
                                          direction: Axis.horizontal,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: <Widget>[
                                            DropdownButton<AbstractWriteHelper>(
                                              value: helper,
                                              items: baseHelper!
                                                  .getAvailableMethods()
                                                  .map<
                                                    DropdownMenuItem<
                                                      AbstractWriteHelper
                                                    >
                                                  >((
                                                    AbstractWriteHelper
                                                    helperClass,
                                                  ) {
                                                    return DropdownMenuItem<
                                                      AbstractWriteHelper
                                                    >(
                                                      value: helperClass,
                                                      child: Text(
                                                        typeLocalization[helperClass
                                                            .name]!,
                                                      ),
                                                    );
                                                  })
                                                  .toList(),
                                              onChanged:
                                                  (
                                                    AbstractWriteHelper?
                                                    helperClass,
                                                  ) {
                                                    setState(() {
                                                      helper = helperClass;
                                                    });
                                                  },
                                            ),
                                            const SizedBox(width: 8),
                                            if (baseHelper!.autoDetect)
                                              TextButton(
                                                onPressed: () async {
                                                  await detectMagicType();
                                                },
                                                child: Text(
                                                  localizations
                                                      .auto_detect_magic_card,
                                                ),
                                              ),
                                          ],
                                        )
                                      : Text(
                                          localizations
                                              .writing_is_not_yet_supported,
                                        ),
                                ),
                              ),
                              isActive: step >= 2,
                            ),
                            Step(
                              title: Text(
                                localizations.write_data_to_magic_card,
                              ),
                              content: Card(
                                child: ListTile(
                                  title: (progress == -1)
                                      ? (helper != null && helper!.isReady())
                                            ? (helper != null &&
                                                      helper!
                                                          .getFailedBlocks()
                                                          .isNotEmpty)
                                                  ? Text(
                                                      "${localizations.otp_magic_warning(localizations.write_data_to_magic_card)} ${localizations.some_blocks_failed_to_write}: ${helper!.getFailedBlocks().join(", ")}",
                                                    )
                                                  : Column(
                                                      children: [
                                                        Text(
                                                          localizations
                                                              .otp_magic_warning(
                                                                localizations
                                                                    .write_data_to_magic_card,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Text(
                                                          localizations
                                                              .keep_stable_warning,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .orange,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    )
                                            : (helper != null &&
                                                  helper!
                                                      .writeWidgetSupported())
                                            ? helper!.getWriteWidget(
                                                context,
                                                setState,
                                              )
                                            : Text(localizations.error)
                                      : LinearProgressIndicator(
                                          value: progress.toDouble() / 100,
                                        ),
                                ),
                              ),
                              isActive: step >= 3,
                            ),
                          ],
                        ),
                      ],
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

class _SimpleWritePanel extends StatelessWidget {
  const _SimpleWritePanel({required this.child});

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
