import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/gui/component/card_list.dart';
import 'package:nlc_toolkit/gui/component/mifare/basic_block_writer.dart';
import 'package:nlc_toolkit/gui/component/mifare/vanity_sak_checkbox.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
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
  const WriteCardPage({super.key});

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

  Future<String?> cardSelectDialog(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
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
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

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
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
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
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
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
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

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

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var typeLocalization = {
      'gen1': localizations.gen1,
      'gen2': localizations.gen2,
      'gen3': localizations.gen3,
      't55xx': localizations.t55xx,
    };

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.write_card)),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: colorScheme.primary,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.basic_write_title,
                              style: textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              localizations.basic_write_description,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const BasicMifareBlockWriter(),
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
