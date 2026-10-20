import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/menu/tools/bcc_calculator.dart';
import 'package:nlc_toolkit/gui/menu/tools/dictionary_download.dart';
import 'package:nlc_toolkit/gui/menu/tools/hf_sniffing.dart';
import 'package:nlc_toolkit/gui/menu/tools/lf_sniffing.dart';
import 'package:nlc_toolkit/gui/menu/tools/mct_import.dart';
import 'package:nlc_toolkit/gui/menu/tools/t55xx_password_cleaner.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ToolItem {
  final String name;
  final String description;
  final IconData icon;
  final bool isDeviceRequired;
  final bool showWipBadge;
  final Widget? onPressed;

  ToolItem({
    required this.name,
    required this.description,
    required this.icon,
    this.isDeviceRequired = false,
    this.showWipBadge = false,
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
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    List<ToolItem> tools = [
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
      appBar: AppBar(title: Text(localizations.tools)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final colors = Theme.of(context).colorScheme;
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.tools,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        localizations.tools_description,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 22),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: constraints.maxWidth >= 880 ? 2 : 1,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          mainAxisExtent: 148,
                        ),
                        itemCount: tools.length,
                        itemBuilder: (context, index) {
                          final tool = tools[index];
                          final disconnected =
                              tool.isDeviceRequired &&
                              !appState.connector!.connected;
                          final available =
                              tool.onPressed != null && !disconnected;
                          return Card(
                            margin: EdgeInsets.zero,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: available
                                  ? () => showDialog(
                                      context: context,
                                      builder: (_) => tool.onPressed!,
                                    )
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: colors.primary.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            tool.icon,
                                            color: colors.primary,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (disconnected || !available)
                                          Text(
                                            disconnected
                                                ? localizations.device_required
                                                : localizations.wip,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                          )
                                        else
                                          Icon(
                                            Icons.arrow_outward_rounded,
                                            color: colors.onSurfaceVariant,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      tool.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      tool.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
