// Enregistrer un badge lu sur un immeuble (Firebase Storage + référence Firestore), et voir les
// badges déjà enregistrés sur un immeuble. Lecture seule de l'ERP par ailleurs (phase 1).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:nlc_toolkit/erp/badge_dumps.dart';
import 'package:nlc_toolkit/erp/erp_http.dart';
import 'package:nlc_toolkit/erp/erp_services.dart';
import 'package:nlc_toolkit/erp/models.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/gui/page/dashboard_labels.dart';
import 'package:nlc_toolkit/gui/page/write_card.dart';
import 'package:nlc_toolkit/helpers/definitions.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';

/// La fréquence situe la technologie du badge ; l'UID et le CUID ne se distinguent pas d'une
/// simple lecture, donc un badge 13,56 MHz est rangé comme « UID » par défaut.
BadgeTech badgeTechForTag(TagType tag) =>
    chameleonTagToFrequency(tag) == TagFrequency.lf
    ? BadgeTech.emT5577
    : BadgeTech.mifareUid;

/// Prépare l'enregistrement d'une carte enregistrée : le contenu sérialisé et de quoi la retrouver.
NewBadgeDump dumpFromCard(CardSave card, {required String siteId}) =>
    NewBadgeDump(
      siteId: siteId,
      bytes: Uint8List.fromList(utf8.encode(card.toJson())),
      name: card.name.trim().isEmpty ? card.uid : card.name.trim(),
      technology: badgeTechForTag(card.tag),
      uid: card.uid,
      tagType: card.tag.value,
    );

/// Ouvre le choix de l'immeuble, puis enregistre la carte dessus.
Future<void> saveCardToSite(BuildContext context, CardSave card) async {
  final site = await _pickSite(context);
  if (site == null || !context.mounted) return;
  final l = AppLocalizations.of(context)!;
  final repo = context.read<ErpServices>().badgeDumps.repo();
  if (repo == null) {
    showNlcToast(context, l.nlc_dumps_offline);
    return;
  }
  try {
    await repo.save(dumpFromCard(card, siteId: site.id));
    if (context.mounted) showNlcToast(context, l.nlc_dump_saved);
  } on ErpException catch (error) {
    if (context.mounted) {
      showNlcToast(context, '${l.nlc_dump_save_failed} ${error.message}');
    }
  }
}

/// Choix d'un immeuble parmi ceux de l'établissement actif (les lieux de passage sont écartés).
Future<BadgeSite?> _pickSite(BuildContext context) {
  final l = AppLocalizations.of(context)!;
  final erp = context.read<ErpServices>();
  final sites =
      (erp.badges.data?.sites ?? const <BadgeSite>[])
          .where((site) => !site.isPlace)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return showDialog<BadgeSite>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Nlc.slate950,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Nlc.radius),
        side: const BorderSide(color: Nlc.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NlcEyebrow('NLC Toolkit', icon: Icons.save_alt_rounded),
              const SizedBox(height: 8),
              Text(
                l.nlc_save_to_site,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.nlc_save_to_site_desc,
                style: const TextStyle(color: Nlc.slate400, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (!erp.badgeDumps.available)
                NlcNotice(tone: NlcTone.warning, message: l.nlc_dumps_offline)
              else if (sites.isEmpty)
                NlcEmptyHint(
                  icon: Icons.apartment_rounded,
                  title: l.nlc_no_sites,
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sites.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) =>
                        _SiteOption(site: sites[i], l: l),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.cancel),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SiteOption extends StatelessWidget {
  const _SiteOption({required this.site, required this.l});

  final BadgeSite site;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final address = [
      site.address,
      [site.postcode, site.city].where((p) => p.isNotEmpty).join(' '),
    ].where((p) => p.isNotEmpty).join(', ');
    return Material(
      color: Nlc.slate900,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, site),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              NlcIconBox(Icons.apartment_rounded, color: Nlc.indigo400),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name.isEmpty ? l.no_name : site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Nlc.slate100,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (address.isNotEmpty)
                      Text(
                        address,
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
              const Icon(Icons.chevron_right_rounded, color: Nlc.slate500),
            ],
          ),
        ),
      ),
    );
  }
}

/// Liste des badges enregistrés sur un immeuble, avec suppression. Chargée à l'affichage.
class SiteDumpsSection extends StatefulWidget {
  const SiteDumpsSection({super.key, required this.siteId});

  final String siteId;

  @override
  State<SiteDumpsSection> createState() => _SiteDumpsSectionState();
}

class _SiteDumpsSectionState extends State<SiteDumpsSection> {
  List<BadgeDump>? _dumps;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SiteDumpsSection old) {
    super.didUpdateWidget(old);
    if (old.siteId != widget.siteId) _load();
  }

  Future<void> _load() async {
    final repo = context.read<ErpServices>().badgeDumps.repo();
    if (repo == null) {
      setState(() {
        _loading = false;
        _dumps = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final dumps = await repo.listForSite(widget.siteId);
      if (!mounted) return;
      setState(() {
        _dumps = dumps;
        _loading = false;
      });
    } on ErpException {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  /// Récupère le dump le temps de l'écrire sur un badge vierge, sans le garder sur l'appareil.
  Future<void> _copy(BadgeDump dump) async {
    final l = AppLocalizations.of(context)!;
    final appState = context.read<NlcAppState>();
    // Un lecteur connecté est indispensable pour écrire.
    if (appState.communicator == null ||
        !(appState.connector?.connected ?? false)) {
      showNlcToast(context, l.nlc_connect_reader_first, success: false);
      return;
    }
    final repo = context.read<ErpServices>().badgeDumps.repo();
    if (repo == null) return;
    showNlcToast(context, l.nlc_copy_fetching);
    try {
      final bytes = await repo.fetch(dump);
      final card = CardSave.fromJson(utf8.decode(bytes));
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WriteCardPage(initialCard: card)),
      );
    } catch (_) {
      // Échec réseau ou dump illisible : rien n'est écrit, rien n'est gardé.
      if (mounted)
        showNlcToast(context, l.nlc_copy_fetch_failed, success: false);
    }
  }

  Future<void> _delete(BadgeDump dump) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Nlc.slate950,
        title: Text(l.nlc_delete_dump),
        content: Text(dump.name.isEmpty ? dump.uid : dump.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = context.read<ErpServices>().badgeDumps.repo();
    if (repo == null) return;
    try {
      await repo.delete(dump);
      if (!mounted) return;
      setState(() => _dumps = _dumps?.where((d) => d.id != dump.id).toList());
      showNlcToast(context, l.nlc_dump_deleted);
    } on ErpException {
      if (mounted) showNlcToast(context, l.nlc_dump_delete_failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Hors connexion ou sans établissement, la section ne s'affiche pas.
    if (!context.read<ErpServices>().badgeDumps.available) {
      return const SizedBox.shrink();
    }
    final dumps = _dumps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: NlcSectionTitle(l.nlc_stored_dumps)),
            if (dumps != null && dumps.isNotEmpty)
              NlcChip('${dumps.length}', color: Nlc.indigo400),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_failed)
          Text(
            l.nlc_dump_delete_failed,
            style: const TextStyle(color: Nlc.rose300, fontSize: 12),
          )
        else if (dumps == null || dumps.isEmpty)
          Text(
            l.nlc_no_stored_dumps,
            style: const TextStyle(color: Nlc.slate500, fontSize: 12),
          )
        else
          for (final dump in dumps)
            _DumpRow(
              dump: dump,
              onCopy: () => _copy(dump),
              onDelete: () => _delete(dump),
            ),
      ],
    );
  }
}

class _DumpRow extends StatelessWidget {
  const _DumpRow({
    required this.dump,
    required this.onCopy,
    required this.onDelete,
  });

  final BadgeDump dump;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final meta = [
      techLabel(l, dump.technology),
      if (dump.createdAt != null)
        DateFormat(
          'd MMM yyyy',
          locale,
        ).format(DateTime.fromMillisecondsSinceEpoch(dump.createdAt!)),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const NlcIconBox(Icons.nfc_rounded, color: Nlc.violet400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dump.name.isEmpty ? dump.uid : dump.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Nlc.slate200, fontSize: 13),
                ),
                Text(
                  meta,
                  style: const TextStyle(color: Nlc.slate500, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.nlc_copy_to_badge,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.contactless_rounded,
              size: 18,
              color: Nlc.indigo400,
            ),
            onPressed: onCopy,
          ),
          IconButton(
            tooltip: l.nlc_delete_dump,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: Nlc.slate400,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
