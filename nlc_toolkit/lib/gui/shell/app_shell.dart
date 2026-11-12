// Coque de l'application, sur le modèle de l'ERP : barre latérale, en-tête avec l'établissement
// actif, et la page courante posée sur le motif de fond.
import 'package:flutter/material.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/models.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/gui/page/connect.dart';
import 'package:nlc_toolkit/gui/page/dashboard.dart';
import 'package:nlc_toolkit/gui/page/debug.dart';
import 'package:nlc_toolkit/gui/page/device_gate.dart';
import 'package:nlc_toolkit/gui/page/flashing.dart';
import 'package:nlc_toolkit/gui/page/home.dart';
import 'package:nlc_toolkit/gui/page/pending_connection.dart';
import 'package:nlc_toolkit/gui/page/read_card.dart';
import 'package:nlc_toolkit/gui/page/saved_cards.dart';
import 'package:nlc_toolkit/gui/page/settings.dart';
import 'package:nlc_toolkit/gui/page/slot_manager.dart';
import 'package:nlc_toolkit/gui/page/tools.dart';
import 'package:nlc_toolkit/gui/page/write_card.dart';
import 'package:nlc_toolkit/gui/shell/navigation.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Largeur à partir de laquelle la barre latérale reste affichée.
const _wideLayout = 900.0;
const _sidebarWidth = 256.0;
const _headerHeight = 64.0;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NlcAppState>().connectDemoDevice();
    });
  }

  @override
  void reassemble() {
    // Rechargement à chaud pendant le développement : repartir d'un appareil déconnecté.
    context.read<NlcAppState>().disconnect();
    super.reassemble();
  }

  Widget _page(
    NlcDestination destination,
    NlcAppState appState,
    AppLocalizations l,
  ) {
    final connector = appState.connector!;
    final connected = connector.connected;
    if (connected && connector.isDFU) return const FlashingPage();

    switch (destination) {
      case NlcDestination.dashboard:
        return const DashboardPage();
      case NlcDestination.read:
        if (!connected) return DeviceNeededPage(title: l.read_card);
        return const DeviceIoGate(isWrite: false, child: ReadCardPage());
      case NlcDestination.write:
        if (!connected) {
          return DeviceNeededPage(
            title: l.write_card,
            icon: Icons.edit_rounded,
          );
        }
        return const DeviceIoGate(isWrite: true, child: WriteCardPage());
      case NlcDestination.library:
        return const SavedCardsPage();
      case NlcDestination.device:
        if (connector.pendingConnection) return const PendingConnectionPage();
        return connected ? const HomePage() : const ConnectPage();
      case NlcDestination.slots:
        if (!connected) {
          return DeviceNeededPage(
            title: l.slot_manager,
            icon: Icons.view_carousel_rounded,
          );
        }
        return const SlotManagerPage();
      case NlcDestination.tools:
        return const ToolsPage();
      case NlcDestination.debug:
        return const DebugPage();
      case NlcDestination.settings:
        return const SettingsMainPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<NlcAppState>();
    final navigation = context.watch<NlcNavigation>();
    final l = AppLocalizations.of(context)!;
    appState.ensureServices();

    final connector = appState.connector!;
    final flashing = connector.connected && connector.isDFU;
    final page = _page(navigation.current, appState, l);
    try {
      WakelockPlus.toggle(enable: flashing);
    } catch (_) {
      // Indisponible sur certaines plateformes : sans conséquence.
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideLayout;
        final sidebar = _Sidebar(
          onNavigate: (destination) {
            navigation.go(destination);
            if (!wide) _scaffoldKey.currentState?.closeDrawer();
          },
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Nlc.canvas,
          drawer: wide || flashing
              ? null
              : Drawer(child: SafeArea(child: sidebar)),
          body: SafeArea(
            child: Row(
              children: [
                if (wide && !flashing)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Nlc.slate950,
                      border: Border(right: BorderSide(color: Nlc.border)),
                    ),
                    child: SizedBox(
                      width: _sidebarWidth,
                      child: _SidebarHost(),
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _Header(
                        showMenu: !wide && !flashing,
                        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                      if (flashing)
                        LinearProgressIndicator(
                          value: appState.progress,
                          minHeight: 3,
                        ),
                      Expanded(
                        child: ClipRect(
                          child: NlcBackground(
                            child: KeyedSubtree(
                              key: ValueKey(
                                '${navigation.current.name}-${page.runtimeType}',
                              ),
                              child: page,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// La barre latérale fixe ferme le tiroir quand on y navigue : ici il n'y en a pas.
class _SidebarHost extends StatelessWidget {
  const _SidebarHost();

  @override
  Widget build(BuildContext context) {
    return _Sidebar(onNavigate: context.read<NlcNavigation>().go);
  }
}

/* ─────────────── Barre latérale ─────────────── */

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.onNavigate});

  final ValueChanged<NlcDestination> onNavigate;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<NlcAppState>();
    final auth = context.watch<AuthController>();
    final navigation = context.watch<NlcNavigation>();
    final l = AppLocalizations.of(context)!;
    final prefs = appState.sharedPreferencesProvider;
    final advanced = appState.advancedMode;
    final issuer = auth.currentIssuer;
    final accent = Nlc.accentFor(issuer?.colorTheme ?? 'indigo');
    final connected = appState.connector?.connected ?? false;

    final destinations = [
      for (final destination in NlcDestination.values)
        if (destination != NlcDestination.debug || appState.devMode)
          if (advanced ||
              !destination.advanced ||
              destination == navigation.current)
            destination,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Nlc.border)),
          ),
          alignment: Alignment.centerLeft,
          child: const NlcBrand(size: 20),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final destination in destinations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _NavItem(
                    icon: destination == navigation.current
                        ? destination.selectedIcon
                        : destination.icon,
                    label: destination.label(l),
                    selected: destination == navigation.current,
                    accent: accent,
                    locked: destination.needsDevice && !connected,
                    onTap: () => onNavigate(destination),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  l.nlc_mode_label.toUpperCase(),
                  style: const TextStyle(
                    color: Nlc.slate500,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              NlcSegmented<bool>(
                value: advanced,
                options: [
                  (value: false, label: l.nlc_mode_simple, icon: null),
                  (value: true, label: l.nlc_mode_advanced, icon: null),
                ],
                onChanged: (value) {
                  prefs.setAdvancedMode(value);
                  appState.changesMade();
                },
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0x80020617),
            border: Border(top: BorderSide(color: Nlc.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.nlc_my_company.toUpperCase(),
                style: const TextStyle(
                  color: Nlc.slate500,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                issuer?.name ?? l.nlc_no_establishment,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Nlc.slate50,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (issuer != null && issuer.siret.isNotEmpty)
                Text(
                  'SIRET : ${issuer.siret}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Nlc.slate400, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Entrée de menu de l'ERP : liseré de couleur à gauche et fond teinté quand elle est active.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final NlcAccent accent;
  final VoidCallback onTap;

  /// La fonction a besoin du lecteur, qui n'est pas connecté.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? accent.text
        : (locked ? Nlc.slate600 : Nlc.slate400);
    return Material(
      color: selected ? accent.wash : Colors.transparent,
      borderRadius: BorderRadius.circular(Nlc.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: Nlc.slate900,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? accent.line : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (locked && !selected)
                const Icon(
                  Icons.usb_off_rounded,
                  size: 14,
                  color: Nlc.slate700,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ─────────────── En-tête ─────────────── */

class _Header extends StatelessWidget {
  const _Header({required this.showMenu, required this.onMenu});

  final bool showMenu;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l = AppLocalizations.of(context)!;
    return Container(
      height: _headerHeight,
      padding: EdgeInsets.only(left: showMenu ? 4 : 24, right: 16),
      decoration: const BoxDecoration(
        color: Nlc.slate950,
        border: Border(bottom: BorderSide(color: Nlc.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Sur un écran étroit, l'établissement garde la place : le nom de l'application et le
          // libellé du lecteur s'effacent.
          final roomy = constraints.maxWidth >= 640;
          return Row(
            children: [
              if (showMenu) ...[
                IconButton(
                  tooltip: l.nlc_menu,
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: onMenu,
                ),
                if (roomy) ...[
                  const SizedBox(width: 4),
                  const NlcBrand(size: 16),
                  const SizedBox(width: 12),
                ],
              ],
              _DeviceChip(showLabel: roomy),
              if (auth.offline) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: l.nlc_dash_offline_text,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: auth.retry,
                    child: roomy
                        ? NlcChip(
                            l.nlc_offline,
                            color: Nlc.amber400,
                            icon: Icons.cloud_off_rounded,
                          )
                        : const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.cloud_off_rounded,
                              size: 18,
                              color: Nlc.amber400,
                            ),
                          ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              const Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _IssuerSwitcher(),
                ),
              ),
              const SizedBox(width: 8),
              const _UserMenu(),
            ],
          );
        },
      ),
    );
  }
}

/// État du lecteur ; un clic mène à la page de l'appareil.
class _DeviceChip extends StatelessWidget {
  const _DeviceChip({this.showLabel = true});

  /// Affiche le nom du lecteur à côté du voyant.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<NlcAppState>();
    final l = AppLocalizations.of(context)!;
    final connector = appState.connector;
    final connected = connector?.connected ?? false;
    final label = connected
        ? 'Chameleon ${chameleonDeviceName(connector!.device)}'
        : l.nlc_device_none;
    if (!showLabel) {
      return Tooltip(
        message: connected
            ? '$label · ${connector!.portName}'
            : l.nlc_connect_device,
        child: InkWell(
          borderRadius: BorderRadius.circular(Nlc.radius),
          onTap: () => context.read<NlcNavigation>().go(NlcDestination.device),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                NlcPulseDot(
                  color: connected ? Nlc.emerald400 : Nlc.slate600,
                  animate: connected,
                ),
                const SizedBox(width: 4),
                Icon(
                  connected ? Icons.usb_rounded : Icons.usb_off_rounded,
                  size: 16,
                  color: connected ? Nlc.emerald300 : Nlc.slate500,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: connected ? connector!.portName : l.nlc_connect_device,
      child: InkWell(
        borderRadius: BorderRadius.circular(Nlc.radius),
        onTap: () => context.read<NlcNavigation>().go(NlcDestination.device),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NlcPulseDot(
                color: connected ? Nlc.emerald400 : Nlc.slate600,
                animate: connected,
              ),
              const SizedBox(width: 6),
              if (connected) ...[
                Icon(
                  connector!.connectionType == ConnectionType.ble
                      ? Icons.bluetooth_rounded
                      : Icons.usb_rounded,
                  size: 15,
                  color: Nlc.emerald300,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: connected ? Nlc.emerald300 : Nlc.slate400,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton de l'établissement actif et liste des établissements, comme dans l'en-tête de l'ERP.
class _IssuerSwitcher extends StatelessWidget {
  const _IssuerSwitcher();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l = AppLocalizations.of(context)!;
    final current = auth.currentIssuer;
    final accent = Nlc.accentFor(current?.colorTheme ?? 'indigo');

    final button = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Nlc.slate900,
        borderRadius: BorderRadius.circular(Nlc.radius),
        border: Border.all(color: Nlc.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accent.line,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              current?.name ?? l.nlc_no_establishment,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Nlc.slate300,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (auth.issuers.length > 1) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Nlc.slate400,
            ),
          ],
        ],
      ),
    );
    if (auth.issuers.length < 2) return button;

    return PopupMenuButton<String>(
      tooltip: l.nlc_establishments,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(
        minWidth: 224,
        maxWidth: 320,
        maxHeight: 360,
      ),
      onSelected: auth.selectIssuer,
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            l.nlc_establishments.toUpperCase(),
            style: const TextStyle(
              color: Nlc.slate500,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        for (final Issuer issuer in auth.issuers)
          PopupMenuItem<String>(
            value: issuer.id,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    issuer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: issuer.id == current?.id
                          ? Colors.white
                          : Nlc.slate300,
                      fontSize: 14,
                      fontWeight: issuer.id == current?.id
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (issuer.id == current?.id)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accent.line,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
      ],
      child: button,
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l = AppLocalizations.of(context)!;
    final email = auth.user?.email ?? '';
    final initial = email.isEmpty ? '?' : email[0].toUpperCase();

    return PopupMenuButton<String>(
      tooltip: email,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      onSelected: (value) {
        if (value == 'settings') {
          context.read<NlcNavigation>().go(NlcDestination.settings);
        }
        if (value == 'signOut') auth.signOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.nlc_settings_signed_in_as.toUpperCase(),
                style: const TextStyle(
                  color: Nlc.slate500,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Nlc.slate200,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'settings',
          child: _MenuRow(icon: Icons.settings_outlined, label: l.settings),
        ),
        PopupMenuItem<String>(
          value: 'signOut',
          child: _MenuRow(
            icon: Icons.logout_rounded,
            label: l.nlc_sign_out,
            color: Nlc.rose300,
          ),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Nlc.indigo500.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Nlc.indigo500.withValues(alpha: 0.35)),
        ),
        child: Text(
          initial,
          style: const TextStyle(
            color: Nlc.indigo300,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.color = Nlc.slate200,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
