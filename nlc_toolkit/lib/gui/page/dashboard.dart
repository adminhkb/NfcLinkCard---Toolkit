// Accueil : l'essentiel de l'espace Badges de l'ERP pour le terrain — rendez-vous à venir, carte des
// immeubles et état du lecteur. Les données sont lues dans l'ERP ; rien n'y est modifié depuis ici.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/badge_controller.dart';
import 'package:nlc_toolkit/erp/badge_stats.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/models.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/component/simple/inline_device_connect.dart';
import 'package:nlc_toolkit/gui/component/simple/reader_source_chooser.dart';
import 'package:nlc_toolkit/gui/component/simple/simple_read_card.dart';
import 'package:nlc_toolkit/gui/component/simple/simple_write_card.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/gui/page/badge_dumps_ui.dart';
import 'package:nlc_toolkit/gui/page/dashboard_labels.dart';
import 'package:nlc_toolkit/gui/page/dashboard_map.dart';
import 'package:nlc_toolkit/gui/shell/navigation.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Nombre de rendez-vous affichés ; les suivants se consultent dans l'ERP.
const _maxAppointments = 8;
const _maxRequests = 4;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _refreshTimer;
  Timer? _clock;
  String? _selectedSiteId;

  @override
  void initState() {
    super.initState();
    // L'ERP est mis à jour en continu ; ici les données sont relues toutes les cinq minutes.
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) context.read<BadgeController>().refresh();
    });
    // « Aujourd'hui », « en retard » : recalculés chaque minute.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) context.read<BadgeController>().recompute();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final badges = context.watch<BadgeController>();
    final erp = context.read<ErpServices>();
    final navigation = context.read<NlcNavigation>();
    final appState = context.watch<NlcAppState>();
    final advanced = appState.advancedMode;
    final l = AppLocalizations.of(context)!;
    final issuer = auth.currentIssuer;
    final data = badges.data;
    final overview = badges.overview;
    final now = DateTime.now().millisecondsSinceEpoch;

    // L'immeuble choisi a pu disparaître ou changer d'établissement.
    final selected = data?.sites
        .where((s) => s.id == _selectedSiteId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NlcPageBody(
        children: [
          NlcPageHeader(
            eyebrow: l.nlc_dash_eyebrow,
            eyebrowIcon: Icons.key_rounded,
            title: l.nlc_dash_title,
            subtitle: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  issuer == null
                      ? l.nlc_dash_no_issuer
                      : l.nlc_dash_subtitle(issuer.name),
                ),
                if (data != null && !auth.offline)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NlcPulseDot(animate: badges.error == null),
                      const SizedBox(width: 2),
                      Text(
                        l.nlc_dash_updated(formatTime(context, data.loadedAt)),
                        style: const TextStyle(
                          color: Nlc.emerald300,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            actions: [
              // En mode avancé, raccourcis vers les onglets Lire/Écrire ; en mode
              // simple, ces fonctions sont des cartes plus bas sur la page.
              if (advanced) ...[
                FilledButton.icon(
                  onPressed: () => navigation.go(NlcDestination.read),
                  icon: const Icon(Icons.nfc_rounded, size: 18),
                  label: Text(l.read_card),
                ),
                OutlinedButton.icon(
                  onPressed: () => navigation.go(NlcDestination.write),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text(l.write_card),
                ),
              ],
              if (erp.config.webAppUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _open(Uri.parse(erp.config.webAppUrl)),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(l.nlc_open_erp),
                ),
              if (badges.available)
                OutlinedButton.icon(
                  onPressed: badges.loading ? null : badges.refresh,
                  icon: badges.loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l.nlc_refresh),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Mode simple : Lire et Écrire vivent ici, en cartes, au lieu d'onglets.
          if (!advanced) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                const read = SimpleReadCard();
                const write = SimpleWriteCard();
                if (constraints.maxWidth < 760) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [read, SizedBox(height: 16), write],
                  );
                }
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: read),
                    SizedBox(width: 16),
                    Expanded(child: write),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          if (auth.offline)
            _StateCard(
              icon: Icons.cloud_off_rounded,
              color: Nlc.amber400,
              title: l.nlc_dash_offline_title,
              text: l.nlc_dash_offline_text,
              action: FilledButton.icon(
                onPressed: auth.retry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l.nlc_retry),
              ),
            )
          else if (issuer == null)
            _StateCard(
              icon: Icons.domain_disabled_rounded,
              color: Nlc.slate400,
              title: l.nlc_no_establishment,
              text: l.nlc_dash_no_issuer,
            )
          else if (data == null || overview == null)
            badges.error != null
                ? _StateCard(
                    icon: Icons.error_outline_rounded,
                    color: Nlc.rose400,
                    title: l.nlc_dash_error_title,
                    text: badges.error!.isOffline
                        ? l.nlc_auth_network
                        : badges.error!.message,
                    action: FilledButton.icon(
                      onPressed: badges.refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l.nlc_retry),
                    ),
                  )
                : _LoadingCard(label: l.nlc_dash_loading)
          else ...[
            if (badges.error != null) ...[
              NlcNotice(
                tone: NlcTone.warning,
                message:
                    '${l.nlc_dash_error_title} — ${badges.error!.isOffline ? l.nlc_auth_network : badges.error!.message}',
              ),
              const SizedBox(height: 16),
            ],
            _Stats(data: data, overview: overview, now: now),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final appointments = _AppointmentsCard(
                  data: data,
                  overview: overview,
                  now: now,
                  onSelectSite: (id) => setState(() => _selectedSiteId = id),
                  erpUrl: erp.config.webAppUrl,
                );
                const device = _DeviceCard();
                final map = SitesMap(
                  sites: data.sites,
                  summaries: overview.sites,
                  selectedId: selected?.id,
                  onSelect: (id) => setState(() => _selectedSiteId = id),
                );
                final panel =
                    selected != null && overview.sites[selected.id] != null
                    ? _SiteDetail(
                        site: selected,
                        summary: overview.sites[selected.id]!,
                        appointments: overview.upcoming
                            .where((s) => s.siteId == selected.id)
                            .toList(),
                        now: now,
                        onClose: () => setState(() => _selectedSiteId = null),
                      )
                    : SiteList(
                        sites: data.sites,
                        summaries: overview.sites,
                        onSelect: (id) => setState(() => _selectedSiteId = id),
                      );
                if (constraints.maxWidth < 980) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      appointments,
                      const SizedBox(height: 16),
                      device,
                      const SizedBox(height: 16),
                      SizedBox(height: 360, child: map),
                      const SizedBox(height: 16),
                      NlcCard(child: panel),
                    ],
                  );
                }
                // Chaque colonne s'empile indépendamment : la carte suit directement
                // les rendez-vous et la liste des immeubles suit directement
                // l'appareil, sans trou entre les deux rangées.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          appointments,
                          const SizedBox(height: 16),
                          SizedBox(height: 480, child: map),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          device,
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 480,
                            child: NlcCard(
                              padding: EdgeInsets.zero,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: panel,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _open(Uri url) async {
  try {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Aucun navigateur disponible : rien à faire de plus.
  }
}

/// Sur téléphone, compose le numéro ; sur ordinateur, le copie pour le coller ailleurs.
Future<void> _contact(BuildContext context, String phone) async {
  final l = AppLocalizations.of(context)!;
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      if (await launchUrl(Uri(scheme: 'tel', path: digits))) return;
    } catch (_) {
      // Pas d'application de téléphone : le numéro est copié à la place.
    }
  }
  await Clipboard.setData(ClipboardData(text: phone));
  if (context.mounted) showNlcToast(context, '${l.nlc_phone_copied} · $phone');
}

/* ─────────────── Indicateurs ─────────────── */

class _Stats extends StatelessWidget {
  const _Stats({required this.data, required this.overview, required this.now});

  final BadgeSnapshot data;
  final BadgeOverview overview;
  final int now;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final today = overview.upcoming
        .where(
          (s) =>
              s.appointmentDate != null &&
              daysBetween(now, s.appointmentDate!) == 0,
        )
        .length;
    final late = overview.upcoming
        .where((s) => isLate(s.appointmentDate, now))
        .length;
    final buildings = data.sites.where((s) => !s.isPlace).toList();
    int withStatus(SiteStatus status) =>
        buildings.where((s) => overview.sites[s.id]?.status == status).length;

    final cards = [
      NlcStatCard(
        label: l.nlc_dash_stat_upcoming,
        value: '${overview.upcoming.length}',
        accent: Nlc.violet500,
        icon: Icons.event_available_rounded,
        valueColor: late > 0 ? Nlc.amber300 : Colors.white,
        footer: [
          l.nlc_dash_today_count(today),
          if (late > 0) l.nlc_dash_late_count(late),
        ].join(' · '),
      ),
      NlcStatCard(
        label: l.nlc_dash_stat_requests,
        value: '${overview.requests.length}',
        accent: Nlc.sky500,
        icon: Icons.phone_callback_rounded,
        footer: l.nlc_dash_requests_footer,
      ),
      NlcStatCard(
        label: l.nlc_dash_stat_sites,
        value: '${buildings.length}',
        accent: Nlc.amber500,
        icon: Icons.apartment_rounded,
        footer: l.nlc_dash_sites_footer(
          withStatus(SiteStatus.client),
          withStatus(SiteStatus.prospecte),
        ),
      ),
      NlcStatCard(
        label: l.nlc_dash_stat_badges,
        value: '${overview.badgesCopied}',
        accent: Nlc.emerald500,
        icon: Icons.key_rounded,
        footer: l.nlc_dash_badges_footer(overview.monthBadges),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : (constraints.maxWidth >= 520 ? 2 : 1);
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += columns) {
          final slice = cards.skip(i).take(columns).toList();
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < slice.length; j++) ...[
                    if (j > 0) const SizedBox(width: 12),
                    Expanded(child: slice[j]),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

/* ─────────────── Rendez-vous ─────────────── */

class _AppointmentsCard extends StatelessWidget {
  const _AppointmentsCard({
    required this.data,
    required this.overview,
    required this.now,
    required this.onSelectSite,
    required this.erpUrl,
  });

  final BadgeSnapshot data;
  final BadgeOverview overview;
  final int now;
  final ValueChanged<String> onSelectSite;
  final String erpUrl;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final sites = {for (final site in data.sites) site.id: site};
    final shown = overview.upcoming.take(_maxAppointments).toList();
    final hidden = overview.upcoming.length - shown.length;
    final requests = overview.requests.take(_maxRequests).toList();

    return NlcCard(
      borderColor: Nlc.violet500.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NlcSectionTitle(
            '${l.nlc_dash_upcoming} · ${overview.upcoming.length}',
            icon: Icons.event_rounded,
            color: Nlc.violet200,
            action: hidden > 0
                ? Text(
                    l.nlc_more_in_erp(hidden),
                    style: const TextStyle(color: Nlc.slate500, fontSize: 11),
                  )
                : null,
          ),
          if (shown.isEmpty)
            NlcEmptyHint(
              icon: Icons.event_busy_rounded,
              title: l.nlc_dash_no_upcoming_title,
              text: l.nlc_dash_no_upcoming_text,
            )
          else
            for (final sale in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AppointmentTile(
                  sale: sale,
                  site: sale.siteId == null ? null : sites[sale.siteId],
                  now: now,
                  onSelectSite: onSelectSite,
                ),
              ),
          if (requests.isNotEmpty) ...[
            const SizedBox(height: 12),
            NlcSectionTitle(
              '${l.nlc_dash_requests} · ${overview.requests.length}',
              icon: Icons.phone_callback_rounded,
              color: Nlc.sky300,
            ),
            for (final sale in requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AppointmentTile(
                  sale: sale,
                  site: sale.siteId == null ? null : sites[sale.siteId],
                  now: now,
                  onSelectSite: onSelectSite,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.sale,
    required this.site,
    required this.now,
    required this.onSelectSite,
  });

  final BadgeSale sale;
  final BadgeSite? site;
  final int now;
  final ValueChanged<String> onSelectSite;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final request = sale.status == BadgeSaleStatus.demande;
    final when = sale.appointmentDate;
    final late = !request && isLate(when, now);
    final today =
        !request && !late && when != null && daysBetween(now, when) == 0;
    final tone = request ? Nlc.sky300 : (late ? Nlc.amber300 : Nlc.violet300);
    final headline = request
        ? '${saleStatusLabel(l, sale.status)} · ${appointmentLabel(context, l, sale.contactDate, now)}'
        : '${appointmentLabel(context, l, when, now)}${late ? ' · ${l.nlc_late}' : ''}';
    final located = site != null && site!.hasPosition;

    final Color background;
    final Color border;
    if (late) {
      background = Nlc.amber500.withValues(alpha: 0.05);
      border = Nlc.amber500.withValues(alpha: 0.3);
    } else if (today) {
      background = Nlc.violet500.withValues(alpha: 0.1);
      border = Nlc.violet500.withValues(alpha: 0.4);
    } else {
      background = Nlc.inset;
      border = Nlc.border;
    }

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Nlc.radius),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: located ? () => onSelectSite(site!.id) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tone,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        text: sale.customerName.isEmpty
                            ? l.nlc_customer
                            : sale.customerName,
                        style: const TextStyle(
                          color: Nlc.slate100,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          if (sale.customerDetail.isNotEmpty)
                            TextSpan(
                              text: ' · ${sale.customerDetail}',
                              style: const TextStyle(
                                color: Nlc.slate400,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        l.nlc_badges_count(sale.quantity),
                        formatEuro(context, sale.price),
                        techLabel(l, sale.technology),
                        site?.name ?? l.nlc_no_site,
                        if (sale.atHome) l.nlc_at_home,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Nlc.slate400,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (sale.customerPhone.isNotEmpty)
                IconButton(
                  tooltip: Platform.isAndroid || Platform.isIOS
                      ? '${l.nlc_call} · ${sale.customerPhone}'
                      : '${l.nlc_copy_phone} · ${sale.customerPhone}',
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  onPressed: () => _contact(context, sale.customerPhone),
                ),
              if (located)
                IconButton(
                  tooltip: l.nlc_directions,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  onPressed: () => _open(directionsUrl(site!.lat!, site!.lng!)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ─────────────── Lecteur ─────────────── */

class _DeviceCard extends StatelessWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<NlcAppState>();
    final navigation = context.read<NlcNavigation>();
    final l = AppLocalizations.of(context)!;
    final connector = appState.connector;
    final connected = connector?.connected ?? false;

    return NlcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NlcSectionTitle(l.nlc_nav_device, icon: Icons.memory_rounded),
          // Choix du lecteur : ChameleonUltra externe ou NFC du téléphone (Android).
          if (!appState.advancedMode) const ReaderSourceChooser(),
          if (!connected && !appState.isPhoneNfc)
            // En mode simple, la connexion se fait dans la carte, sans ouvrir d'onglet.
            (!appState.advancedMode
                ? const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: InlineDeviceConnect(),
                  )
                : NlcEmptyHint(
                    icon: Icons.usb_off_rounded,
                    title: l.nlc_dash_device_missing,
                    text: l.nlc_dash_device_missing_text,
                    action: FilledButton.icon(
                      onPressed: () => navigation.go(NlcDestination.device),
                      icon: const Icon(Icons.usb_rounded, size: 18),
                      label: Text(l.nlc_connect_device),
                    ),
                  ))
          else ...[
            Row(
              children: [
                NlcIconBox(
                  appState.isPhoneNfc
                      ? Icons.contactless_rounded
                      : (connector!.connectionType == ConnectionType.ble
                          ? Icons.bluetooth_rounded
                          : Icons.usb_rounded),
                  color: Nlc.emerald400,
                  size: 46,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appState.isPhoneNfc
                            ? (Localizations.localeOf(context).languageCode ==
                                    'fr'
                                ? 'NFC du téléphone'
                                : 'Phone NFC')
                            : 'Chameleon ${chameleonDeviceName(connector!.device)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        connector!.portName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Nlc.slate400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                NlcChip(l.nlc_dash_device_ready, color: Nlc.emerald400),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!appState.isPhoneNfc)
                  OutlinedButton.icon(
                    onPressed: () => navigation.go(NlcDestination.device),
                    icon: const Icon(Icons.memory_rounded, size: 18),
                    label: Text(l.device_dashboard),
                  ),
                OutlinedButton.icon(
                  onPressed: () => appState.isPhoneNfc
                      ? appState.useExternalReader()
                      : appState.disconnect(manual: true),
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: Text(l.disconnect_device),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/* ─────────────── Fiche d'un immeuble ─────────────── */

class _SiteDetail extends StatelessWidget {
  const _SiteDetail({
    required this.site,
    required this.summary,
    required this.appointments,
    required this.now,
    required this.onClose,
  });

  final BadgeSite site;
  final SiteSummary summary;
  final List<BadgeSale> appointments;
  final int now;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final address = [
      if (site.address.isNotEmpty) site.address,
      [site.postcode, site.city].where((part) => part.isNotEmpty).join(' '),
    ].where((part) => part.isNotEmpty).join(', ');
    final details = [
      siteKindLabel(l, site.kind),
      if (!site.isPlace && site.units != null) l.nlc_units_count(site.units!),
      if (!site.isPlace && site.accessSystem.isNotEmpty) site.accessSystem,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  NlcChip(
                    siteStatusLabel(l, summary.status),
                    color: siteStatusColor(summary.status),
                  ),
                  if (!site.isPlace)
                    NlcChip(
                      compatibilityLabel(l, site.compatibility),
                      color: compatibilityColor(site.compatibility),
                    ),
                  if (site.doNotProspect)
                    NlcChip(l.nlc_site_do_not_prospect, color: Nlc.rose400),
                ],
              ),
            ),
            IconButton(
              tooltip: l.nlc_close,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          site.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            address,
            style: const TextStyle(color: Nlc.slate400, fontSize: 12),
          ),
        ],
        const SizedBox(height: 2),
        Text(
          details,
          style: const TextStyle(color: Nlc.slate500, fontSize: 11),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: site.isPlace
                  ? NlcMini(
                      label: l.nlc_site_calls_brought,
                      value: '${summary.broughtContacts}',
                      sub: l.nlc_site_copied(summary.broughtCopies),
                    )
                  : NlcMini(
                      label: l.nlc_site_contacts,
                      value: '${summary.contacts}',
                      sub: summary.openLeads > 0
                          ? l.nlc_site_in_progress(summary.openLeads)
                          : l.nlc_site_copied(summary.copies),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NlcMini(
                label: l.nlc_site_badges,
                value:
                    '${site.isPlace ? summary.broughtBadges : summary.badges}',
                sub: site.isPlace ? l.nlc_site_thanks_to_place : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NlcMini(
                label: l.nlc_site_posters,
                value: '${summary.activePosters}',
              ),
            ),
          ],
        ),
        if (site.hasPosition) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _open(directionsUrl(site.lat!, site.lng!)),
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: Text(l.nlc_directions),
            ),
          ),
        ],
        const SizedBox(height: 18),
        NlcSectionTitle(l.nlc_site_appointments),
        if (appointments.isEmpty)
          Text(
            l.nlc_site_no_appointment,
            style: const TextStyle(color: Nlc.slate500, fontSize: 12),
          )
        else
          for (final sale in appointments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appointmentLabel(
                            context,
                            l,
                            sale.appointmentDate,
                            now,
                          ),
                          style: TextStyle(
                            color: isLate(sale.appointmentDate, now)
                                ? Nlc.amber300
                                : Nlc.violet300,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            sale.customerName.isEmpty
                                ? l.nlc_customer
                                : sale.customerName,
                            if (sale.customerDetail.isNotEmpty)
                              sale.customerDetail,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Nlc.slate200,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    l.nlc_badges_count(sale.quantity),
                    style: const TextStyle(color: Nlc.slate400, fontSize: 11),
                  ),
                ],
              ),
            ),
        if (site.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            site.notes.trim(),
            style: const TextStyle(
              color: Nlc.slate400,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
        // Badges enregistrés sur cet immeuble (Firebase Storage).
        SiteDumpsSection(siteId: site.id),
      ],
    );
  }
}

/* ─────────────── États : chargement, erreur, hors connexion ─────────────── */

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return NlcCard(
      borderColor: color.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        children: [
          NlcIconBox(icon, color: color, size: 50),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Nlc.slate400,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 14),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Nlc.slate400,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
