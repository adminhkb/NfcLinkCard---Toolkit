import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdvancedPage extends StatelessWidget {
  const AdvancedPage({super.key, required this.onSelect});

  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final connected = appState.connector?.connected ?? false;
    final french = Localizations.localeOf(context).languageCode == 'fr';

    final sections = <_AdvancedSection>[
      _AdvancedSection(
        title: french ? 'Bibliothèque' : 'Library',
        entries: [
          _AdvancedEntry(
            pageIndex: 5,
            icon: Icons.folder_copy_outlined,
            title: localizations.saved_cards,
            description: localizations.saved_cards_description,
          ),
        ],
      ),
      _AdvancedSection(
        title: french ? 'Appareil' : 'Device',
        entries: [
          _AdvancedEntry(
            pageIndex: 9,
            icon: Icons.nfc_outlined,
            title: localizations.device_dashboard,
            description: localizations.device_dashboard_description,
            requiresDevice: true,
          ),
          _AdvancedEntry(
            pageIndex: 4,
            icon: Icons.view_carousel_outlined,
            title: localizations.slot_manager,
            description: localizations.slot_manager_description,
            requiresDevice: true,
          ),
        ],
      ),
      _AdvancedSection(
        title: french ? 'Outils' : 'Tools',
        entries: [
          _AdvancedEntry(
            pageIndex: 6,
            icon: Icons.construction_outlined,
            title: localizations.tools,
            description: localizations.tools_description,
          ),
          if (appState.devMode)
            _AdvancedEntry(
              pageIndex: 8,
              icon: Icons.bug_report_outlined,
              title: localizations.debug,
              description: localizations.debug_description,
            ),
        ],
      ),
      _AdvancedSection(
        title: french ? 'Préférences' : 'Preferences',
        entries: [
          _AdvancedEntry(
            pageIndex: 7,
            icon: Icons.tune_outlined,
            title: localizations.settings,
            description: localizations.settings_description,
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth > 1160
              ? 1080.0
              : constraints.maxWidth;
          final twoColumns = contentWidth >= 680;
          final sidePadding = constraints.maxWidth < 600 ? 20.0 : 36.0;
          final tileWidth = twoColumns
              ? (contentWidth - sidePadding * 2 - 14) / 2
              : contentWidth - sidePadding * 2;

          return SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    sidePadding,
                    constraints.maxWidth < 600 ? 28 : 44,
                    sidePadding,
                    48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NLC TOOLKIT  /  ${french ? 'ESPACE AVANCÉ' : 'ADVANCED'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        localizations.advanced,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        localizations.advanced_description,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 26),
                      _ConnectionNote(connected: connected, french: french),
                      const SizedBox(height: 34),
                      for (final section in sections) ...[
                        _SectionHeader(title: section.title),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final entry in section.entries)
                              SizedBox(
                                width: tileWidth,
                                child: _AdvancedTile(
                                  entry: entry,
                                  enabled: !entry.requiresDevice || connected,
                                  connectionRequired: french
                                      ? 'Connexion requise'
                                      : 'Connection required',
                                  onTap: () => onSelect(entry.pageIndex),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 30),
                      ],
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

class _ConnectionNote extends StatelessWidget {
  const _ConnectionNote({required this.connected, required this.french});

  final bool connected;
  final bool french;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle_outline : Icons.info_outline,
            size: 19,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected
                  ? (french
                        ? 'Appareil connecté : toutes les fonctions sont disponibles.'
                        : 'Device connected: all features are available.')
                  : (french
                        ? 'Connectez votre appareil pour accéder aux fonctions matérielles.'
                        : 'Connect your device to access hardware features.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AdvancedTile extends StatelessWidget {
  const _AdvancedTile({
    required this.entry,
    required this.enabled,
    required this.connectionRequired,
    required this.onTap,
  });

  final _AdvancedEntry entry;
  final bool enabled;
  final String connectionRequired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: enabled
                          ? colors.primary.withValues(alpha: 0.12)
                          : colors.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      entry.icon,
                      size: 22,
                      color: enabled ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: enabled
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          enabled ? entry.description : connectionRequired,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    enabled ? Icons.arrow_forward_rounded : Icons.lock_outline,
                    size: 18,
                    color: enabled ? colors.primary : colors.onSurfaceVariant,
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

class _AdvancedSection {
  const _AdvancedSection({required this.title, required this.entries});

  final String title;
  final List<_AdvancedEntry> entries;
}

class _AdvancedEntry {
  const _AdvancedEntry({
    required this.pageIndex,
    required this.icon,
    required this.title,
    required this.description,
    this.requiresDevice = false,
  });

  final int pageIndex;
  final IconData icon;
  final String title;
  final String description;
  final bool requiresDevice;
}
