// Carte des immeubles : mêmes repères que dans l'ERP (pastille colorée par statut, nombre de badges
// copiés au centre, carré pour un lieu de passage), sur un fond OpenStreetMap assombri.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nlc_toolkit/erp/badge_stats.dart';
import 'package:nlc_toolkit/erp/models.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/gui/page/dashboard_labels.dart';

/// Orléans : centre de la carte tant qu'aucun immeuble n'a de position, comme dans l'ERP.
const _defaultCenter = LatLng(47.9029, 1.9093);

class SitesMap extends StatefulWidget {
  const SitesMap({
    super.key,
    required this.sites,
    required this.summaries,
    required this.selectedId,
    required this.onSelect,
  });

  /// Tous les immeubles ; seuls ceux qui ont une position sont dessinés.
  final List<BadgeSite> sites;
  final Map<String, SiteSummary> summaries;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  /// Les tests d'interface coupent le fond de carte pour ne dépendre d'aucun serveur.
  @visibleForTesting
  static bool tilesEnabled = true;

  @override
  State<SitesMap> createState() => _SitesMapState();
}

class _SitesMapState extends State<SitesMap> {
  final _controller = MapController();
  bool _ready = false;

  List<BadgeSite> get _located => [
    for (final site in widget.sites)
      if (site.hasPosition && widget.summaries.containsKey(site.id)) site,
  ];

  LatLng _point(BadgeSite site) => LatLng(site.lat!, site.lng!);

  @override
  void didUpdateWidget(SitesMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Centrer sur l'immeuble choisi dans une liste, pas à chaque mise à jour des données.
    final selected = widget.selectedId;
    if (!_ready || selected == null || selected == oldWidget.selectedId) return;
    final site = _located.where((s) => s.id == selected).firstOrNull;
    if (site == null) return;
    final zoom = _controller.camera.zoom < 15 ? 16.0 : _controller.camera.zoom;
    _controller.move(_point(site), zoom);
  }

  void _fitAll() {
    final located = _located;
    if (!_ready || located.isEmpty) return;
    if (located.length == 1) {
      _controller.move(_point(located.single), 16);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: located.map(_point).toList(),
        padding: const EdgeInsets.all(56),
        maxZoom: 17,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final located = _located;
    // Le repère choisi est dessiné en dernier, au-dessus des autres.
    final ordered = [
      ...located.where((s) => s.id != widget.selectedId),
      ...located.where((s) => s.id == widget.selectedId),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(Nlc.radiusCard),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Nlc.slate900,
          border: Border.all(color: Nlc.border),
          borderRadius: BorderRadius.circular(Nlc.radiusCard),
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: located.length == 1
                    ? _point(located.single)
                    : _defaultCenter,
                initialZoom: located.length == 1 ? 16 : 13,
                initialCameraFit: located.length < 2
                    ? null
                    : CameraFit.coordinates(
                        coordinates: located.map(_point).toList(),
                        padding: const EdgeInsets.all(56),
                        maxZoom: 17,
                      ),
                minZoom: 4,
                maxZoom: 19,
                backgroundColor: Nlc.slate900,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, _) => widget.onSelect(null),
                onMapReady: () => _ready = true,
              ),
              children: [
                if (SitesMap.tilesEnabled)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.nfclinkcard.nlctoolkit',
                    maxNativeZoom: 19,
                    tileBuilder: _nightTileBuilder,
                  ),
                MarkerLayer(
                  markers: [
                    for (final site in ordered)
                      _marker(
                        l,
                        site,
                        widget.summaries[site.id]!,
                        site.id == widget.selectedId,
                      ),
                  ],
                ),
              ],
            ),
            if (located.length > 1)
              Positioned(
                top: 12,
                left: 12,
                child: _OverlayButton(
                  icon: Icons.fit_screen_rounded,
                  label: l.nlc_map_fit,
                  onTap: _fitAll,
                ),
              ),
            Positioned(
              left: 12,
              bottom: 12,
              right: 96,
              child: _Legend(showPlace: located.any((s) => s.isPlace)),
            ),
            if (located.isEmpty)
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 380),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xD9020617),
                      borderRadius: BorderRadius.circular(Nlc.radius),
                      border: Border.all(color: Nlc.slate700),
                    ),
                    child: Text(
                      l.nlc_map_empty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Nlc.slate300, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Marker _marker(
    AppLocalizations l,
    BadgeSite site,
    SiteSummary summary,
    bool selected,
  ) {
    final size = selected ? 42.0 : 32.0;
    // Pour un lieu de passage : les badges copiés grâce à son affiche.
    final badges = site.isPlace ? summary.broughtBadges : summary.badges;
    final contacts = site.isPlace ? summary.broughtContacts : summary.contacts;
    final tooltip = [
      site.name,
      site.isPlace ? l.nlc_site_kind_place : siteStatusLabel(l, summary.status),
      l.nlc_contacts_count(contacts),
      l.nlc_badges_count(badges),
    ].join(' · ');

    return Marker(
      point: _point(site),
      width: size,
      height: size,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () => widget.onSelect(site.id),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: siteStatusColor(summary.status),
                borderRadius: BorderRadius.circular(site.isPlace ? 9 : size),
                border: Border.all(
                  color: selected ? Colors.white : const Color(0xD9020617),
                  width: 3,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x73000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Text(
                badges > 0 ? '$badges' : '',
                style: const TextStyle(
                  color: Nlc.slate950,
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ramène le fond OpenStreetMap aux bleus nuit de l'interface : les zones claires deviennent
/// sombres, les textes et les contours deviennent clairs, sans autre couleur.
Widget _nightTileBuilder(
  BuildContext context,
  Widget tileWidget,
  TileImage tile,
) {
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix(<double>[
      -0.117, -0.393, -0.040, 0, 158, //
      -0.125, -0.421, -0.042, 0, 174, //
      -0.146, -0.491, -0.050, 0, 215, //
      0, 0, 0, 1, 0,
    ]),
    child: tileWidget,
  );
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xD9020617),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Nlc.radius),
        side: const BorderSide(color: Nlc.slate700),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Nlc.slate100),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Nlc.slate100,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.showPlace});

  final bool showPlace;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    Widget entry(Widget mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Nlc.slate300,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xD9020617),
          borderRadius: BorderRadius.circular(Nlc.radius),
          border: Border.all(color: Nlc.slate700),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final status in SiteStatus.values)
              entry(
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: siteStatusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                siteStatusLabel(l, status),
              ),
            if (showPlace)
              entry(
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Nlc.slate400),
                  ),
                ),
                l.nlc_site_kind_place,
              ),
          ],
        ),
      ),
    );
  }
}

/// Liste des immeubles à côté de la carte, les clients d'abord.
class SiteList extends StatefulWidget {
  const SiteList({
    super.key,
    required this.sites,
    required this.summaries,
    required this.onSelect,
  });

  final List<BadgeSite> sites;
  final Map<String, SiteSummary> summaries;
  final ValueChanged<String> onSelect;

  /// Hauteur maximale de la liste : au-delà, elle défile avec sa propre barre.
  static const double maxListHeight = 320;

  @override
  State<SiteList> createState() => _SiteListState();
}

class _SiteListState extends State<SiteList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sites = widget.sites;
    final summaries = widget.summaries;
    final onSelect = widget.onSelect;
    final l = AppLocalizations.of(context)!;
    int badges(BadgeSite s) =>
        s.isPlace ? summaries[s.id]!.broughtBadges : summaries[s.id]!.badges;
    int contacts(BadgeSite s) => s.isPlace
        ? summaries[s.id]!.broughtContacts
        : summaries[s.id]!.contacts;
    final ranked =
        [
          for (final site in sites)
            if (summaries.containsKey(site.id)) site,
        ]..sort((a, b) {
          final byBadges = badges(b).compareTo(badges(a));
          if (byBadges != 0) return byBadges;
          final byContacts = contacts(b).compareTo(contacts(a));
          if (byContacts != 0) return byContacts;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NlcSectionTitle(l.nlc_map_ranking),
        if (ranked.isEmpty)
          NlcEmptyHint(
            icon: Icons.apartment_rounded,
            title: l.nlc_map_no_sites,
            text: l.nlc_map_no_sites_text,
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: SiteList.maxListHeight,
            ),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: ListView(
                controller: _scroll,
                shrinkWrap: true,
                padding: const EdgeInsets.only(right: 12),
                children: [
                  for (final site in ranked)
                    InkWell(
                      borderRadius: BorderRadius.circular(Nlc.radius),
                      onTap: () => onSelect(site.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: siteStatusColor(
                                  summaries[site.id]!.status,
                                ),
                                borderRadius: BorderRadius.circular(
                                  site.isPlace ? 3 : 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    site.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Nlc.slate100,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    [
                                      if (site.isPlace) l.nlc_site_kind_place,
                                      siteStatusLabel(
                                        l,
                                        summaries[site.id]!.status,
                                      ),
                                      l.nlc_contacts_count(contacts(site)),
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Nlc.slate500,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l.nlc_badges_count(badges(site)),
                              style: const TextStyle(
                                color: Nlc.slate300,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
