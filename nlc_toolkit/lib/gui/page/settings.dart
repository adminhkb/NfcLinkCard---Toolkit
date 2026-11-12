import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/component/qrcode_viewer.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/gui/menu/dialogs/qr/import.dart';
import 'package:nlc_toolkit/gui/menu/dialogs/qr/settings.dart';
import 'package:nlc_toolkit/helpers/interchange_formats.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

Future<String> loadLicense(String license) async {
  return await rootBundle.loadString('assets/licenses/$license.md');
}

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  SettingsMainPageState createState() => SettingsMainPageState();
}

class SettingsMainPageState extends State<SettingsMainPage> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  /* ─────────────── Export et import des réglages ─────────────── */

  Future<void> _exportAsQrCodes() async {
    final appState = context.read<NlcAppState>();
    final settingsJson = appState.sharedPreferencesProvider
        .dumpSettingsToJson();
    final Map<String, int> options =
        await showDialog(
          context: context,
          builder: (_) => const QRCodeSettings(),
        ) ??
        {};
    if (options.isEmpty || !mounted) return;

    final chunks = splitStringIntoQrChunks(settingsJson, options['splitSize']!);
    chunks.insert(
      0,
      jsonEncode({
        'Info': InterchangeFormat.settingsQrHeader,
        'chunks': chunks.length,
        'sha256': sha256
            .convert(const Utf8Encoder().convert(settingsJson))
            .toString(),
      }),
    );
    await showDialog(
      context: context,
      builder: (_) => QrCodeViewer(
        qrChunks: chunks,
        errorCorrection: options['errorCorrection']!,
      ),
    );
    appState.changesMade();
  }

  Future<void> _exportAsFile() async {
    final appState = context.read<NlcAppState>();
    final l = AppLocalizations.of(context)!;
    await FilePicker.saveFile(
      dialogTitle: '${l.output_file}:',
      fileName: 'NLCToolkitSettings.json',
      bytes: const Utf8Encoder().convert(
        appState.sharedPreferencesProvider.dumpSettingsToJson(),
      ),
    );
  }

  Future<void> _importFromQrCodes() async {
    final appState = context.read<NlcAppState>();
    final l = AppLocalizations.of(context)!;
    if (!(Platform.isAndroid || Platform.isIOS)) {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l.error),
          content: Text(l.qr_code_import_not_supported_description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l.ok),
            ),
          ],
        ),
      );
      return;
    }
    final String? settingsJson = await showDialog(
      context: context,
      builder: (_) => const QrCodeImport(),
    );
    if (settingsJson == null) return;
    appState.sharedPreferencesProvider.restoreSettingsFromJson(settingsJson);
    appState.changesMade();
  }

  Future<void> _importFromFile() async {
    final appState = context.read<NlcAppState>();
    final PlatformFile? picked = await FilePicker.pickFile();
    if (picked == null) return;
    final contents = await File(picked.path!).readAsBytes();
    appState.sharedPreferencesProvider.restoreSettingsFromJson(
      const Utf8Decoder().convert(contents),
    );
    appState.changesMade();
  }

  /// Propose le QR code ou le fichier, puis lance [onQrCode] ou [onFile].
  void _chooseTransfer({
    required String title,
    required String text,
    required Future<void> Function() onQrCode,
    required Future<void> Function() onFile,
  }) {
    final l = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.cancel),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onQrCode();
            },
            child: Text(l.qr_code),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onFile();
            },
            child: Text(l.json_file),
          ),
        ],
      ),
    );
  }

  /* ─────────────── À propos ─────────────── */

  Future<void> _showLicenses() async {
    final licenses = {
      'BSD-3-Clause': await loadLicense('BSD-3-Clause'),
      'GPL3': await loadLicense('GPL3'),
      'LGPL3': await loadLicense('LGPL3'),
      'MIT': await loadLicense('MIT'),
    };
    void register(String package, String license) => LicenseRegistry.addLicense(
      () => Stream<LicenseEntry>.value(
        LicenseEntryWithLineBreaks(<String>[package], licenses[license]!),
      ),
    );
    register('chinese_font_library', 'BSD-3-Clause'); // helpers/font.dart
    register('FlipperNestedRecovery', 'LGPL3'); // hardnested porté pour Windows
    register('proxmark3', 'GPL3');
    register('minlzma', 'MIT'); // décompression des tables hardnested
    if (mounted) {
      showLicensePage(context: context, applicationName: 'NLC Toolkit');
    }
  }

  Future<void> _showLegalNotices() async {
    final l = AppLocalizations.of(context)!;
    final notice = await rootBundle.loadString('NOTICE.md');
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.nlc_legal_notices),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              notice,
              style: const TextStyle(
                color: Nlc.slate300,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.ok),
          ),
        ],
      ),
    );
  }

  void _confirmToggle({
    required String title,
    required String text,
    required VoidCallback onConfirm,
  }) {
    final l = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(dialogContext);
            },
            child: Text(l.ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<NlcAppState>();
    final auth = context.watch<AuthController>();
    final l = AppLocalizations.of(context)!;
    final prefs = appState.sharedPreferencesProvider;
    final emulated = prefs.isEmulatedChameleon();
    final debugMode = prefs.isDebugMode();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NlcPageBody(
        maxWidth: 820,
        children: [
          NlcPageHeader(
            eyebrow: 'NLC Toolkit',
            eyebrowIcon: Icons.settings_rounded,
            title: l.settings,
            subtitle: Text(l.settings_description),
          ),
          const SizedBox(height: 24),
          _Section(
            title: l.nlc_settings_account,
            icon: Icons.shield_outlined,
            children: [
              _Row(
                title:
                    '${l.nlc_settings_signed_in_as} ${auth.user?.email ?? '—'}',
                trailing: OutlinedButton.icon(
                  onPressed: () => auth.signOut(),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(l.nlc_sign_out),
                ),
              ),
              const Divider(height: 24),
              _Row(
                title: l.nlc_2fa_title,
                subtitle: auth.hasTrustedDevice
                    ? l.nlc_settings_device_remembered
                    : l.nlc_settings_device_not_remembered,
                trailing: auth.hasTrustedDevice
                    ? OutlinedButton(
                        onPressed: () async {
                          await auth.forgetThisDevice();
                          if (context.mounted) {
                            showNlcToast(
                              context,
                              l.nlc_settings_forget_device_done,
                            );
                          }
                        },
                        child: Text(l.nlc_settings_forget_device),
                      )
                    : null,
              ),
            ],
          ),
          _Section(
            title: l.nlc_settings_display,
            icon: Icons.palette_outlined,
            children: [
              _Row(
                title: l.nlc_mode_label,
                subtitle: l.nlc_mode_hint,
                trailing: SizedBox(
                  width: 220,
                  child: NlcSegmented<bool>(
                    value: appState.advancedMode,
                    options: [
                      (value: false, label: l.nlc_mode_simple, icon: null),
                      (value: true, label: l.nlc_mode_advanced, icon: null),
                    ],
                    onChanged: (value) {
                      prefs.setAdvancedMode(value);
                      appState.changesMade();
                    },
                  ),
                ),
              ),
              const Divider(height: 24),
              _Row(
                title: l.language,
                trailing: DropdownButton<String>(
                  value: prefs.getLocale().toLanguageTag(),
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(Nlc.radius),
                  dropdownColor: Nlc.slate950,
                  onChanged: (value) {
                    final parts = (value ?? 'en').split('-');
                    prefs.setLocale(
                      Locale(parts.first, parts.length > 1 ? parts.last : null),
                    );
                    appState.changesMade();
                  },
                  items: [
                    for (final locale in AppLocalizations.supportedLocales)
                      DropdownMenuItem(
                        value: locale.toLanguageTag(),
                        child: Text(
                          lookupAppLocalizations(locale).language_name,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            title: l.settings_section_connection,
            icon: Icons.usb_rounded,
            children: [
              _Switch(
                title: l.auto_scan_devices,
                value: prefs.getAutoScanEnabled(),
                onChanged: (value) {
                  prefs.setAutoScanEnabled(value);
                  appState.changesMade();
                },
              ),
              _Switch(
                title: l.auto_connect_first_device,
                value: prefs.getAutoConnectFirstFoundDevice(),
                onChanged: (value) {
                  prefs.setAutoConnectFirstFoundDevice(value);
                  appState.changesMade();
                },
              ),
            ],
          ),
          _Section(
            title: l.settings_section_data,
            icon: Icons.folder_outlined,
            children: [
              _Switch(
                title: l.confirm_deletions,
                value: prefs.getConfirmDelete(),
                onChanged: (value) {
                  prefs.setConfirmDelete(value);
                  appState.changesMade();
                },
              ),
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _chooseTransfer(
                      title: l.choose_export_method,
                      text: l.choose_export_method_description,
                      onQrCode: _exportAsQrCodes,
                      onFile: _exportAsFile,
                    ),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(l.export_settings),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _chooseTransfer(
                      title: l.import_settings,
                      text: l.import_settings_description,
                      onQrCode: _importFromQrCodes,
                      onFile: _importFromFile,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(l.import_settings),
                  ),
                ],
              ),
            ],
          ),
          _Section(
            title: l.about,
            icon: Icons.info_outline_rounded,
            children: [
              FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  return _Row(
                    title: 'NLC Toolkit',
                    subtitle: info == null
                        ? l.about_text
                        : '${l.version} ${info.version} (${info.buildNumber})\n${l.about_text}',
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                l.nlc_about_license_text,
                style: const TextStyle(
                  color: Nlc.slate400,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  l.trademarks_mifare,
                  l.trademarks_em,
                  l.trademarks_hid,
                ].join('\n'),
                style: const TextStyle(
                  color: Nlc.slate500,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _showLegalNotices,
                    icon: const Icon(Icons.gavel_rounded, size: 18),
                    label: Text(l.nlc_legal_notices),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showLicenses,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: Text(l.licenses),
                  ),
                ],
              ),
            ],
          ),
          _Section(
            title: l.settings_section_developer,
            icon: Icons.code_rounded,
            children: [
              _Switch(
                title: l.emulate_device,
                value: emulated,
                onChanged: (_) => _confirmToggle(
                  title: l.emulate_device,
                  text: l.emulate_device_confirmation(
                    (emulated ? l.deactivate : l.activate).toLowerCase(),
                  ),
                  onConfirm: () {
                    prefs.setEmulatedChameleon(!emulated);
                    // Le connecteur est recréé au prochain affichage.
                    appState.connector = null;
                    appState.changesMade();
                  },
                ),
              ),
              _Switch(
                title: l.debug_mode,
                value: debugMode,
                onChanged: (_) => _confirmToggle(
                  title: l.debug_mode,
                  text: l.debug_mode_confirmation(
                    (debugMode ? l.deactivate : l.activate).toLowerCase(),
                  ),
                  onConfirm: () {
                    prefs.setDebugMode(!debugMode);
                    appState.changesMade();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NlcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NlcSectionTitle(title, icon: icon),
            const SizedBox(height: 2),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Ligne de réglage : intitulé et précision à gauche, commande à droite (dessous si la place manque).
class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Nlc.slate100,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: const TextStyle(
              color: Nlc.slate400,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
    if (trailing == null) return text;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [text, const SizedBox(height: 10), trailing!],
          );
        }
        return Row(
          children: [
            Expanded(child: text),
            const SizedBox(width: 16),
            trailing!,
          ],
        );
      },
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: const TextStyle(
          color: Nlc.slate100,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
