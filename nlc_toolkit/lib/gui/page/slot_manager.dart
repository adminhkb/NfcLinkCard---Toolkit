import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/gui/component/card_list.dart';
import 'package:nlc_toolkit/gui/component/error_page.dart';
import 'package:nlc_toolkit/gui/menu/dialogs/slot/settings.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/helpers/hf14a4_slot.dart';
import 'package:nlc_toolkit/helpers/mifare_classic/general.dart';
import 'package:nlc_toolkit/helpers/mifare_ultralight/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';

class SlotManagerPage extends StatefulWidget {
  const SlotManagerPage({super.key});

  @override
  SlotManagerPageState createState() => SlotManagerPageState();
}

class SlotManagerPageState extends State<SlotManagerPage> {
  List<SlotTypes> usedSlots = List.generate(8, (_) => SlotTypes());

  List<EnabledSlotInfo> enabledSlots = List.generate(
    8,
    (_) => EnabledSlotInfo(),
  );

  List<SlotNames> slotData = List.generate(8, (_) => SlotNames());

  int progress = -1;
  int gridPosition = 0;
  bool onlyOneSlot = false;
  Future<void>? _slotLoadFuture;

  Future<void> loadSlotData() async {
    if (progress != -1) {
      return;
    }

    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    usedSlots = await appState.communicator!.getSlotTagTypes();
    enabledSlots = await appState.communicator!.getEnabledSlots();
    slotData = await appState.communicator!.getSlotTagNames();

    for (SlotNames slot in slotData) {
      slot.hf = slot.hf.isEmpty ? localizations.no_name : slot.hf;
      slot.lf = slot.lf.isEmpty ? localizations.no_name : slot.lf;
    }
  }

  void refreshSlot() {
    _slotLoadFuture = null;
    setUploadState(-1);

    var appState = context.read<ChameleonGUIState>();
    appState.changesMade();
  }

  void setUploadState(int progressBar) {
    setState(() {
      progress = progressBar;
    });

    var appState = context.read<ChameleonGUIState>();
    appState.changesMade();
  }

  Future<void> onTap(
    CardSave card,
    dynamic close,
    AppLocalizations localizations,
  ) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    if (isMifareClassic(card.tag)) {
      close(context, card.name);
      setUploadState(0);
      var isEV1 = chameleonTagSaveCheckForMifareClassicEV1(card);
      if (isEV1) {
        card.tag = TagType.mifare2K;
      }

      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.hf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      var cardData = CardData(
        uid: hexToBytes(card.uid),
        atqa: card.atqa,
        sak: card.sak,
        ats: card.ats,
      );
      await appState.communicator!.setMf1AntiCollision(cardData);

      List<int> blockChunk = [];
      int lastSend = 0;

      for (
        var blockOffset = 0;
        blockOffset <
            mfClassicGetBlockCount(chameleonTagTypeGetMfClassicType(card.tag));
        blockOffset++
      ) {
        if ((card.data.length > blockOffset &&
                card.data[blockOffset].isEmpty) ||
            blockChunk.length >= 128) {
          if (blockChunk.isNotEmpty) {
            await appState.communicator!.setMf1BlockData(
              lastSend,
              Uint8List.fromList(blockChunk),
            );
            blockChunk = [];
            lastSend = blockOffset;
          }
        }

        if (card.data.length > blockOffset &&
            card.data[blockOffset].length == 16) {
          blockChunk.addAll(card.data[blockOffset]);
        }

        setUploadState(
          (blockOffset /
                  mfClassicGetBlockCount(
                    chameleonTagTypeGetMfClassicType(card.tag),
                  ) *
                  100)
              .round(),
        );
        await asyncSleep(1);
      }

      if (blockChunk.isNotEmpty) {
        await appState.communicator!.setMf1BlockData(
          lastSend,
          Uint8List.fromList(blockChunk),
        );
      }

      setUploadState(100);

      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.hf,
      );
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (card.tag == TagType.hf14a4) {
      close(context, card.name);
      setUploadState(0);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.hf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await writeHf14a4SlotIdentity(appState.communicator!, card);
      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.hf,
      );
      await appState.communicator!.saveSlotData();
      setUploadState(100);
      appState.changesMade();
      refreshSlot();
    } else if (isEM410X(card.tag)) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.lf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      TagType slotTagType = card.tag == TagType.em410XElectra
          ? TagType.em410XElectra
          : TagType.em410X;
      await appState.communicator!.setSlotType(gridPosition, slotTagType);
      await appState.communicator!.setDefaultDataToSlot(
        gridPosition,
        slotTagType,
      );
      await appState.communicator!.setEM410XEmulatorID(hexToBytes(card.uid));
      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.lf,
      );
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (card.tag == TagType.hidProx) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.lf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!.setHIDProxEmulatorID(
        hexToBytes(HIDCard.fromUID(card.uid).toString()),
      );
      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.lf,
      );
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (card.tag == TagType.viking) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.lf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!.setVikingEmulatorID(hexToBytes(card.uid));
      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.lf,
      );
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (card.tag == TagType.pac) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.lf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!.setPacEmulatorID(hexToBytes(card.uid));
      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.lf,
      );
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (card.tag == TagType.ioProx) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.lf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!.setIoProxEmulatorID(hexToBytes(card.uid));
      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.lf,
      );
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (card.tag == TagType.idteck) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.lf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!.setIdteckEmulatorID(hexToBytes(card.uid));
      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.lf,
      );
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (isMifareUltralight(card.tag)) {
      close(context, card.name);
      setUploadState(0);

      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!.enableSlot(
        gridPosition,
        TagFrequency.hf,
        true,
      );
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      var cardData = CardData(
        uid: hexToBytes(card.uid),
        atqa: card.atqa,
        sak: card.sak,
        ats: card.ats,
      );
      await appState.communicator!.setMf1AntiCollision(cardData);

      for (
        var page = 0;
        page < mfUltralightGetPagesCount(card.tag) && card.data.length > page;
        page++
      ) {
        await appState.communicator!.mf0EmulatorWritePages(
          page,
          card.data[page],
        );

        setUploadState(
          (page / mfUltralightGetPagesCount(card.tag) * 100).round(),
        );

        await asyncSleep(1);
      }

      if (card.extraData.ultralightVersion.isNotEmpty) {
        await appState.communicator!.mf0EmulatorSetVersionData(
          card.extraData.ultralightVersion,
        );
      }

      if (card.extraData.ultralightSignature.isNotEmpty) {
        await appState.communicator!.mf0EmulatorSetSignatureData(
          card.extraData.ultralightSignature,
        );
      }

      if (card.extraData.ultralightCounters.isNotEmpty) {
        for (int i = 0; i < card.extraData.ultralightCounters.length; i++) {
          await appState.communicator!.mf0EmulatorSetCounterData(
            i,
            card.extraData.ultralightCounters[i],
            true,
          );
        }
      }

      if (mfUltralightHasCounters(card.tag)) {
        await appState.communicator!.mf0ResetAuthCount();
      }

      setUploadState(100);

      await appState.communicator!.setSlotTagName(
        gridPosition,
        (card.name.isEmpty) ? localizations.no_name : card.name,
        TagFrequency.hf,
      );
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else {
      appState.log!.e("Can't write this card type yet.");
      close(context, card.name);
    }
  }

  Future<String?> cardSelectDialog(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var tags = appState.sharedPreferencesProvider.getCards();

    // Don't allow user to upload more tags while already uploading dump
    if (progress != -1) {
      return Future.value("");
    }

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(cards: tags, onTap: onTap),
    );
  }

  void _chooseCardForSlot(int index) {
    setState(() => gridPosition = index);
    cardSelectDialog(context);
  }

  void _openSlotSettings(int index) {
    showDialog(
      context: context,
      builder: (dialogContext) =>
          SlotSettings(slot: index, refresh: refreshSlot),
    );
  }

  Widget _buildSlotCard(int index, AppLocalizations localizations) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = enabledSlots[index].any();

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => _chooseCardForSlot(index),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.layers_rounded,
                          color: scheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${localizations.slot} ${index + 1}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (active
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          active
                              ? localizations.enabled
                              : localizations.disabled,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: active
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SlotFrequencyRow(
                    label: localizations.hf,
                    icon: Icons.credit_card_rounded,
                    name: slotData[index].hf,
                    type: chameleonTagToString(
                      usedSlots[index].hf,
                      localizations,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SlotFrequencyRow(
                    label: localizations.lf,
                    icon: Icons.wifi_rounded,
                    name: slotData[index].lf,
                    type: chameleonTagToString(
                      usedSlots[index].lf,
                      localizations,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _chooseCardForSlot(index),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(
                      localizations.select_saved_card,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: localizations.slot_settings,
                  onPressed: () => _openSlotSettings(index),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connector = appState.connector!;
    final bluetooth = connector.connectionType == ConnectionType.ble;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(localizations.slot_manager),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 20 : 32,
                  vertical: compact ? 22 : 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.slots,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: compact ? 30 : 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      localizations.slot_manager_description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              bluetooth
                                  ? Icons.bluetooth_rounded
                                  : Icons.usb_rounded,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  localizations.chameleon_connected,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Chameleon ${chameleonDeviceName(connector.device)} · ${connector.portName}',
                                  style: theme.textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.check_circle_rounded,
                            color: scheme.primary,
                            size: 21,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: FutureBuilder<void>(
                        future: _slotLoadFuture ??= loadSlotData(),
                        builder: (context, snapshot) {
                          if (progress != -1) {
                            return Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 460,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Icon(
                                        Icons.upload_rounded,
                                        color: scheme.primary,
                                        size: 34,
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        localizations.uploading_dump,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      LinearProgressIndicator(
                                        value: (progress / 100).toDouble(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(height: 15),
                                  Text(localizations.please_wait),
                                ],
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            connector.performDisconnect();
                            return ErrorPage(
                              errorMessage: snapshot.error.toString(),
                            );
                          }
                          return LayoutBuilder(
                            builder: (context, listConstraints) {
                              final columns = listConstraints.maxWidth >= 1000
                                  ? 3
                                  : listConstraints.maxWidth >= 620
                                  ? 2
                                  : 1;
                              return AlignedGridView.count(
                                padding: const EdgeInsets.only(bottom: 24),
                                crossAxisCount: columns,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                itemCount: 8,
                                itemBuilder: (context, index) =>
                                    _buildSlotCard(index, localizations),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SlotFrequencyRow extends StatelessWidget {
  const _SlotFrequencyRow({
    required this.label,
    required this.icon,
    required this.name,
    required this.type,
  });

  final String label;
  final IconData icon;
  final String name;
  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.secondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
