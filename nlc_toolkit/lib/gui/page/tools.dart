import 'package:flutter/material.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/gui/menu/tools/bcc_calculator.dart';
import 'package:nlc_toolkit/gui/menu/tools/dictionary_download.dart';
import 'package:nlc_toolkit/gui/menu/tools/hf_sniffing.dart';
import 'package:nlc_toolkit/gui/menu/tools/lf_sniffing.dart';
import 'package:nlc_toolkit/gui/menu/tools/mct_import.dart';
import 'package:nlc_toolkit/gui/menu/tools/t55xx_password_cleaner.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:provider/provider.dart';

class ToolItem {
  final String name;
  final String description;
  final IconData icon;
  final bool isDeviceRequired;
  final Widget? onPressed;

  ToolItem({
    required this.name,
    required this.description,
    required this.icon,
    this.isDeviceRequired = false,
    this.onPressed,
  });
}

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  ToolsPageState createState() => ToolsPageState();
}

class ToolsPageState extends State<ToolsPage> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<NlcAppState>();
    final localizations = AppLocalizations.of(context)!;
    final connected = appState.connector?.connected ?? false;

    final tools = [
      ToolItem(
        name: localizations.bcc_calculator,
        description: localizations.bcc_calculator_description,
        icon: Icons.calculate_outlined,
        onPressed: const BccCalculatorMenu(),
      ),
      ToolItem(
        name: localizations.mct_import,
        description: localizations.mct_import_description,
        icon: Icons.upload_file,
        onPressed: const MctImportMenu(),
      ),
      ToolItem(
        name: localizations.dictionary_download,
        description: localizations.dictionary_download_description,
        icon: Icons.key,
        onPressed: const DictionaryDownloadMenu(),
      ),
      ToolItem(
        name: localizations.t55xx_password_cleaner,
        description: localizations.t55xx_password_cleaner_description,
        icon: Icons.password,
        onPressed: const T55XXPasswordCleanerMenu(),
        isDeviceRequired: true,
      ),
      ToolItem(
        name: localizations.lf_sniffing,
        description: localizations.lf_sniffing_description,
        icon: Icons.graphic_eq,
        onPressed: const LfSniffingMenu(),
      ),
      ToolItem(
        name: localizations.hf_sniffing,
        description: localizations.hf_sniffing_description,
        icon: Icons.radar,
        onPressed: const HfSniffingMenu(),
      ),
      ToolItem(
        name: localizations.mifare_classic_gen4,
        description: localizations.mifare_classic_gen4_description,
        icon: Icons.settings,
        isDeviceRequired: true,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NlcPageBody(
        maxWidth: 1080,
        children: [
          NlcPageHeader(
            eyebrow: 'NLC Toolkit',
            eyebrowIcon: Icons.construction_rounded,
            title: localizations.tools,
            subtitle: Text(localizations.tools_description),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final tool in tools)
                    SizedBox(
                      width: width,
                      child: NlcActionTile(
                        icon: tool.icon,
                        title: tool.name,
                        description: tool.description,
                        // Outil pas encore disponible, ou lecteur absent.
                        enabled:
                            tool.onPressed != null &&
                            (!tool.isDeviceRequired || connected),
                        disabledHint: tool.onPressed == null
                            ? '${localizations.wip} · ${tool.description}'
                            : localizations.device_required,
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => tool.onPressed!,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
