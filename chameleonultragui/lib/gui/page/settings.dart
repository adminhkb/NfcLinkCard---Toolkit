import 'package:chameleonultragui/gui/component/developer_list.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/gui/menu/dialogs/qr/settings.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/helpers/open_collective.dart';
import 'package:chameleonultragui/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:chameleonultragui/gui/component/qrcode_viewer.dart';
import 'package:crypto/crypto.dart';
import 'package:chameleonultragui/gui/menu/dialogs/qr/import.dart';
import 'package:chameleonultragui/gui/menu/pages/changelog_view.dart';
import 'package:flutter/services.dart' show rootBundle;

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

Future<String> loadLicense(String license) async {
  return await rootBundle.loadString('assets/licenses/$license.md');
}

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  SettingsMainPageState createState() => SettingsMainPageState();
}

class SettingsMainPageState extends State<SettingsMainPage> {
  @override
  void initState() {
    super.initState();
  }

  Future<(String, List<Map<String, String>>, PackageInfo)>
      getFutureData() async {
    return (
      await fetchOCnames(),
      await fetchContributors(),
      await PackageInfo.fromPlatform()
    );
  }

  Future<String> fetchOCnames() async {
    final List<String> names = await fetchOpenCollectiveContributors();

    if (names.isEmpty && mounted) {
      return AppLocalizations.of(context)!.failed_to_fetch_oc_contributors;
    }

    String finalNames = "";
    for (String name in names) {
      finalNames += "$name, ";
    }
    return finalNames.substring(0, finalNames.length - 2);
  }

  Future<List<Map<String, String>>> fetchContributors() async {
    return await fetchGitHubContributors();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.settings),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsSection(
                    title: localizations.settings_section_appearance,
                    icon: Icons.palette_outlined,
                    children: [
              Text(localizations.sidebar_expansion,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              ToggleButtonsWrapper(
                  key: ValueKey(
                      'sidebar-${Localizations.localeOf(context).toLanguageTag()}'),
                  items: [
                    localizations.expand,
                    localizations.auto,
                    localizations.retract
                  ],
                  selectedValue: appState.sharedPreferencesProvider
                      .getSideBarExpandedIndex(),
                  onChange: (int index) async {
                    if (index == 0) {
                      appState.sharedPreferencesProvider
                          .setSideBarExpanded(true);
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(false);
                    } else if (index == 2) {
                      appState.sharedPreferencesProvider
                          .setSideBarExpanded(false);
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(false);
                    } else {
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(true);
                    }
                    appState.sharedPreferencesProvider
                        .setSideBarExpandedIndex(index);
                    appState.changesMade();

                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => updateNavigationRailWidth(context));
                  }),
              const SizedBox(height: 10),
              Text(
                localizations.theme,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              ToggleButtonsWrapper(
                  key: ValueKey(
                      'theme-${Localizations.localeOf(context).toLanguageTag()}'),
                  items: [
                    localizations.system,
                    localizations.light,
                    localizations.dark
                  ],
                  selectedValue:
                      appState.sharedPreferencesProvider.getTheme().index,
                  onChange: (int index) async {
                    appState.sharedPreferencesProvider
                        .setTheme(ThemeMode.values[index]);
                    appState.changesMade();
                  }),
              const SizedBox(height: 10),
              Text(
                localizations.language,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: DropdownButton(
                  value: appState.sharedPreferencesProvider
                      .getLocale()
                      .toLanguageTag(),
                  onChanged: (value) {
                    final parts = (value ?? 'en').split('-');
                    appState.sharedPreferencesProvider
                        .setLocale(Locale(parts.first,
                            parts.length > 1 ? parts.last : null));
                    appState.changesMade();
                  },
                  items: AppLocalizations.supportedLocales.map((locale) {
                    final localeLocalizations = lookupAppLocalizations(locale);
                    return DropdownMenuItem(
                        value: locale.toLanguageTag(),
                        child: Text(localeLocalizations.language_name));
                  }).toList(),
                ),
              ),
                    ],
                  ),
                  _SettingsSection(
                    title: localizations.settings_section_connection,
                    icon: Icons.bluetooth_connected_outlined,
                    children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SwitchListTile(
                  title: Text(
                    localizations.auto_scan_devices,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  value: appState.sharedPreferencesProvider.getAutoScanEnabled(),
                  onChanged: (value) async {
                    appState.sharedPreferencesProvider.setAutoScanEnabled(value);
                    appState.changesMade();
                  },
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SwitchListTile(
                  title: Text(
                    localizations.auto_connect_first_device,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  value: appState.sharedPreferencesProvider
                      .getAutoConnectFirstFoundDevice(),
                  onChanged: (value) async {
                    appState.sharedPreferencesProvider
                        .setAutoConnectFirstFoundDevice(value);
                    appState.changesMade();
                  },
                ),
              ),
                    ],
                  ),
                  _SettingsSection(
                    title: localizations.settings_section_data,
                    icon: Icons.folder_outlined,
                    children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SwitchListTile(
                  title: Text(
                    localizations.confirm_deletions,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  value: appState.sharedPreferencesProvider.getConfirmDelete(),
                  onChanged: (value) async {
                    appState.sharedPreferencesProvider.setConfirmDelete(value);
                    appState.changesMade();
                  },
                ),
              ),
              const SizedBox(height: 10),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: TextButton(
                    onPressed: () => showDialog<String>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: Text(AppLocalizations.of(context)!
                                .choose_export_method),
                            content: Text(AppLocalizations.of(context)!
                                .choose_export_method_description),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(localizations.cancel),
                              ),
                              TextButton(
                                onPressed: () async {
                                  String string = appState
                                      .sharedPreferencesProvider
                                      .dumpSettingsToJson();

                                  Map<String, int> settings = await showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return const QRCodeSettings();
                                          }) ??
                                      {};

                                  if (settings.isEmpty) {
                                    return;
                                  }

                                  List<String> qrChunks =
                                      splitStringIntoQrChunks(string,
                                          settings["splitSize"]!); //2048

                                  // Generate Header Info
                                  Map<String, dynamic> headerData = {
                                    "Info": "Chameleon Ultra GUI Settings",
                                    "chunks": qrChunks.length,
                                    "sha256": sha256
                                        .convert(
                                            const Utf8Encoder().convert(string))
                                        .toString(),
                                  };
                                  qrChunks.insert(0, jsonEncode(headerData));

                                  if (context.mounted) {
                                    await showDialog(
                                      context: context,
                                      builder: (BuildContext context) =>
                                          QrCodeViewer(
                                              qrChunks: qrChunks,
                                              errorCorrection:
                                                  settings["errorCorrection"]!),
                                    );
                                  }

                                  appState.changesMade();
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                                child: Text(localizations.qr_code),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await FilePicker.saveFile(
                                    dialogTitle:
                                        '${localizations.output_file}:',
                                    fileName: 'NLCToolkitSettings.json',
                                    bytes: const Utf8Encoder().convert(appState
                                        .sharedPreferencesProvider
                                        .dumpSettingsToJson()),
                                  );
                                },
                                child: Text(
                                    AppLocalizations.of(context)!.json_file),
                              ),
                            ],
                          ),
                        ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppLocalizations.of(context)!.export_settings),
                        const Icon(Icons.upload)
                      ],
                    )),
              ),
              const SizedBox(height: 10),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: TextButton(
                  onPressed: () => showDialog<String>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title:
                          Text(AppLocalizations.of(context)!.import_settings),
                      content: Text(AppLocalizations.of(context)!
                          .import_settings_description),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(localizations.cancel),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (!(Platform.isAndroid || Platform.isIOS)) {
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title:
                                      Text(AppLocalizations.of(context)!.error),
                                  content: Text(AppLocalizations.of(context)!
                                      .qr_code_import_not_supported_description),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(localizations.ok),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            String? jsonData = await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return const QrCodeImport();
                                });

                            if (jsonData == null) {
                              return;
                            }
                            appState.sharedPreferencesProvider
                                .restoreSettingsFromJson(jsonData);

                            appState.changesMade();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          child: Text(localizations.qr_code),
                        ),
                        TextButton(
                          onPressed: () async {
                            PlatformFile? result = await FilePicker.pickFile();
                            if (result != null) {
                              File file = File(result.path!);
                              var contents = await file.readAsBytes();
                              var string =
                                  const Utf8Decoder().convert(contents);
                              appState.sharedPreferencesProvider
                                  .restoreSettingsFromJson(string);
                              appState.changesMade();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            }
                          },
                          child: Text(AppLocalizations.of(context)!.json_file),
                        ),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppLocalizations.of(context)!.import_settings),
                      const Icon(Icons.download),
                    ],
                  ),
                ),
              ),
                    ],
                  ),
                  _SettingsSection(
                    title: localizations.about,
                    icon: Icons.info_outline_rounded,
                    children: [
              TextButton(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.about),
                    content: Center(
                      child: FutureBuilder(
                        future: getFutureData(),
                        builder:
                            (BuildContext context, AsyncSnapshot snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          } else if (snapshot.hasError) {
                            appState.connector!.performDisconnect();
                            return ErrorPage(
                                errorMessage: snapshot.error.toString());
                          } else {
                            final (names, contributors, packageInfo) =
                                snapshot.data;
                            return SingleChildScrollView(
                                child: Column(
                              children: [
                                const Text('NLC Toolkit',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                Text(localizations.about_text),
                                const SizedBox(height: 10),
                                Text('${localizations.version}:'),
                                Text(
                                    '${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                Text('${localizations.developed_by}:'),
                                const SizedBox(height: 10),
                                DeveloperList(avatars: developers),
                                const SizedBox(height: 10),
                                Text('${localizations.license}:'),
                                 const Text('GNU General Public License v3.0',
                                     style:
                                         TextStyle(fontWeight: FontWeight.bold)),
                                 const SizedBox(height: 10),
                                 Text(localizations.based_on_chameleon_gui),
                                 const SizedBox(height: 6),
                                 GestureDetector(
                                    onTap: () async {
                                      await launchUrl(Uri.parse(
                                          'https://github.com/GameTec-live/ChameleonUltraGUI'));
                                    },
                                    child: const Text(
                                        'https://github.com/GameTec-live/ChameleonUltraGUI')),
                                const SizedBox(height: 30),
                                GestureDetector(
                                    onTap: () async {
                                      await launchUrl(Uri.parse(
                                          'https://opencollective.com/chameleon-ultra-gui'));
                                    },
                                    child:
                                        Text(localizations.thanks_for_support)),
                                const SizedBox(height: 10),
                                Text(names,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                Text('${localizations.code_contributors}:'),
                                const SizedBox(height: 10),
                                DeveloperList(avatars: contributors),
                                const SizedBox(height: 10),
                                Text(localizations.trademarks_mifare),
                                const SizedBox(height: 10),
                                Text(localizations.trademarks_em),
                                const SizedBox(height: 10),
                                Text(localizations.trademarks_hid),
                              ],
                            ));
                          }
                        },
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                ),
                child: Text(localizations.about),
              ),
              const SizedBox(height: 10),
              TextButton(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () async {
                  Map<String, String> licenses = {
                    'BSD-3-Clause': await loadLicense('BSD-3-Clause'),
                    'GPL3': await loadLicense('GPL3'),
                    'LGPL3': await loadLicense('LGPL3'),
                    'MIT': await loadLicense('MIT')
                  };

                  // font.dart
                  LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(
                        LicenseEntryWithLineBreaks(
                          <String>['chinese_font_library'],
                          licenses['BSD-3-Clause']!,
                        ),
                      ));

                  // ported hardnested to Windows + MSVC, separation from proxmark3 code
                  LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(
                        LicenseEntryWithLineBreaks(
                          <String>['FlipperNestedRecovery'],
                          licenses['LGPL3']!,
                        ),
                      ));

                  LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(
                        LicenseEntryWithLineBreaks(
                          <String>['proxmark3'],
                          licenses['GPL3']!,
                        ),
                      ));

                  // hardnested tables uncompressor
                  LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(
                        LicenseEntryWithLineBreaks(
                          <String>['minlzma'],
                          licenses['MIT']!,
                        ),
                      ));

                  if (context.mounted) {
                    showLicensePage(context: context);
                  }
                },
                child: Text(localizations.licenses),
              ),
              const SizedBox(height: 10),
              TextButton(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => const ChangelogView(),
                ),
                child: Text(localizations.changelog),
              ),
              const SizedBox(height: 10),
              TextButton(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () async {
                  await launchUrl(Uri.parse(
                      'https://crowdin.com/project/chameleonultragui'));
                },
                child: Text(localizations.help_translate),
              ),
                    ],
                  ),
                  _SettingsSection(
                    title: localizations.settings_section_developer,
                    icon: Icons.code_rounded,
                    children: [
              TextButton(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.emulate_device),
                    content: Text(localizations.emulate_device_confirmation(
                        appState.sharedPreferencesProvider.isEmulatedChameleon()
                            ? localizations.deactivate.toLowerCase()
                            : localizations.activate.toLowerCase())),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.cancel),
                      ),
                      TextButton(
                        onPressed: () {
                          appState.sharedPreferencesProvider
                              .setEmulatedChameleon(!appState
                                  .sharedPreferencesProvider
                                  .isEmulatedChameleon());
                          appState.connector = null;
                          appState.changesMade();
                          Navigator.pop(context);
                        },
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                ),
                child: Text(
                    "${appState.sharedPreferencesProvider.isEmulatedChameleon() ? localizations.deactivate : localizations.activate} ${localizations.emulate_device.toLowerCase()}"),
              ),
              const SizedBox(height: 10),
              TextButton(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.debug_mode),
                    content: Text(localizations.debug_mode_confirmation(
                        appState.sharedPreferencesProvider.isDebugMode()
                            ? localizations.deactivate.toLowerCase()
                            : localizations.activate.toLowerCase())),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.cancel),
                      ),
                      TextButton(
                        onPressed: () {
                          appState.sharedPreferencesProvider.setDebugMode(
                              !appState.sharedPreferencesProvider
                                  .isDebugMode());
                          appState.changesMade();
                          Navigator.pop(context);
                        },
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                ),
                child: Text(
                    "${appState.sharedPreferencesProvider.isDebugMode() ? localizations.deactivate : localizations.activate} ${localizations.debug_mode.toLowerCase()}"),
              ),
                    ],
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: colors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: colors.outlineVariant, height: 1),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
