// Enregistrer un badge lu sur un immeuble (Firebase Storage + référence Firestore), et voir les
// badges déjà enregistrés sur un immeuble. Lecture seule de l'ERP par ailleurs (phase 1).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:nlc_toolkit/connector/serial_abstract.dart';
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
import 'package:nlc_toolkit/helpers/simple_dump.dart';
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
  final french = Localizations.localeOf(context).languageCode == 'fr';
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
              Row(
                children: [
                  if (erp.badges.available)
                    TextButton.icon(
                      onPressed: () async {
                        final created = await showDialog<BadgeSite>(
                          context: context,
                          builder: (_) => const _CreateSiteDialog(),
                        );
                        if (created != null && context.mounted) {
                          Navigator.pop(context, created);
                        }
                      },
                      icon: const Icon(Icons.add_business_rounded, size: 18),
                      label: Text(french ? 'Créer un immeuble' : 'New building'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Formulaire de création d'un immeuble, repris de l'ERP (mêmes champs) pour pouvoir
/// enregistrer un badge sur un immeuble qui n'existe pas encore. Renvoie la fiche créée.
class _CreateSiteDialog extends StatefulWidget {
  const _CreateSiteDialog();

  @override
  State<_CreateSiteDialog> createState() => _CreateSiteDialogState();
}

class _CreateSiteDialogState extends State<_CreateSiteDialog> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _postcode = TextEditingController();
  final _city = TextEditingController();
  final _units = TextEditingController();
  final _accessSystem = TextEditingController();
  final _notes = TextEditingController();

  // Les lieux de passage se créent dans l'ERP ; ici on ne propose que des immeubles.
  static const _kinds = [
    BadgeSiteKind.immeuble,
    BadgeSiteKind.residence,
    BadgeSiteKind.parking,
    BadgeSiteKind.bureaux,
    BadgeSiteKind.maison,
    BadgeSiteKind.autre,
  ];

  BadgeSiteKind _kind = BadgeSiteKind.immeuble;
  BadgeCompatibility _compatibility = BadgeCompatibility.inconnue;
  bool _doNotProspect = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _postcode.dispose();
    _city.dispose();
    _units.dispose();
    _accessSystem.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(bool french) async {
    final name = _name.text.trim();
    final address = _address.text.trim();
    final finalName = name.isNotEmpty ? name : address;
    if (finalName.isEmpty) {
      setState(
        () => _error = french
            ? "Donnez un nom ou une adresse à l'immeuble."
            : 'Give the building a name or an address.',
      );
      return;
    }
    int? units;
    final unitsText = _units.text.trim();
    if (unitsText.isNotEmpty) {
      final parsed = int.tryParse(unitsText);
      if (parsed == null || parsed < 0) {
        setState(
          () => _error = french
              ? 'Nombre de logements invalide.'
              : 'Invalid number of units.',
        );
        return;
      }
      units = parsed;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final site = await context.read<ErpServices>().badges.createSite(
        name: finalName,
        address: address,
        city: _city.text.trim(),
        postcode: _postcode.text.trim(),
        kind: _kind,
        units: units,
        accessSystem: _accessSystem.text.trim(),
        compatibility: _compatibility,
        doNotProspect: _doNotProspect,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, site);
    } on ErpException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = french ? 'Création impossible.' : 'Could not create.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final french = Localizations.localeOf(context).languageCode == 'fr';

    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );

    return Dialog(
      backgroundColor: Nlc.slate950,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Nlc.radius),
        side: const BorderSide(color: Nlc.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NlcEyebrow('NLC Toolkit', icon: Icons.add_business_rounded),
              const SizedBox(height: 8),
              Text(
                french ? 'Créer un immeuble' : 'New building',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.words,
                        decoration: deco(french ? 'Nom' : 'Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _address,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.words,
                        decoration: deco(french ? 'Adresse' : 'Address'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _postcode,
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9]'),
                                ),
                              ],
                              decoration: deco(
                                french ? 'Code postal' : 'Postcode',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _city,
                              enabled: !_saving,
                              textCapitalization: TextCapitalization.words,
                              decoration: deco(french ? 'Ville' : 'City'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<BadgeSiteKind>(
                        initialValue: _kind,
                        decoration: deco(french ? 'Type' : 'Type'),
                        items: [
                          for (final kind in _kinds)
                            DropdownMenuItem(
                              value: kind,
                              child: Text(kind.label),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) =>
                                  setState(() => _kind = value ?? _kind),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _units,
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9]'),
                                ),
                              ],
                              decoration: deco(french ? 'Logements' : 'Units'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _accessSystem,
                              enabled: !_saving,
                              decoration: deco(
                                french ? 'Système d\'accès' : 'Access system',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<BadgeCompatibility>(
                        initialValue: _compatibility,
                        decoration: deco(
                          french ? 'Compatibilité' : 'Compatibility',
                        ),
                        items: [
                          for (final c in BadgeCompatibility.values)
                            DropdownMenuItem(value: c, child: Text(c.label)),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(
                                () => _compatibility = value ?? _compatibility,
                              ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notes,
                        enabled: !_saving,
                        maxLines: 2,
                        decoration: deco('Notes'),
                      ),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _doNotProspect,
                        onChanged: _saving
                            ? null
                            : (v) =>
                                  setState(() => _doNotProspect = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          french ? 'Ne pas prospecter' : 'Do not prospect',
                          style: const TextStyle(
                            color: Nlc.slate200,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Nlc.rose300, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(l.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : () => _submit(french),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  bool _reading = false;
  String? _readStep;

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
      if (mounted) {
        showNlcToast(context, l.nlc_copy_fetch_failed, success: false);
      }
    }
  }

  /// Lit un badge et l'enregistre directement sur cet immeuble (Firebase Storage), sans passer
  /// par la bibliothèque locale ni le choix de l'immeuble.
  Future<void> _readAndSave() async {
    final l = AppLocalizations.of(context)!;
    final appState = context.read<NlcAppState>();
    final connector = appState.connector;
    if (appState.communicator == null || !(connector?.connected ?? false)) {
      showNlcToast(context, l.nlc_connect_reader_first, success: false);
      return;
    }
    if (connector?.device != ChameleonDevice.ultra) {
      showNlcToast(context, l.lite_no_read, success: false);
      return;
    }
    final repo = context.read<ErpServices>().badgeDumps.repo();
    if (repo == null) {
      showNlcToast(context, l.nlc_dumps_offline, success: false);
      return;
    }
    setState(() {
      _reading = true;
      _readStep = simpleDumpStepLabel(SimpleDumpStep.reading, l);
    });
    try {
      final card = await readSimpleDump(
        context,
        appState,
        l,
        onStep: (step) {
          if (mounted) setState(() => _readStep = simpleDumpStepLabel(step, l));
        },
      );
      if (!mounted) return;
      if (card == null) {
        showNlcToast(context, l.no_card_found, success: false);
        return;
      }
      await repo.save(dumpFromCard(card, siteId: widget.siteId));
      if (!mounted) return;
      showNlcToast(context, l.nlc_dump_saved);
      await _load();
    } on ErpException catch (error) {
      if (mounted) {
        showNlcToast(
          context,
          '${l.nlc_dump_save_failed} ${error.message}',
          success: false,
        );
      }
    } catch (_) {
      if (mounted) {
        showNlcToast(context, l.nlc_copy_fetch_failed, success: false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _reading = false;
          _readStep = null;
        });
      }
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
    final french = Localizations.localeOf(context).languageCode == 'fr';
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
        const SizedBox(height: 10),
        // Lire un badge et l'enregistrer directement sur cet immeuble.
        FilledButton.icon(
          onPressed: _reading ? null : _readAndSave,
          icon: _reading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.contactless_rounded, size: 18),
          label: Text(
            _reading
                ? (_readStep ?? (french ? 'Lecture…' : 'Reading…'))
                : (french ? 'Lire le tag' : 'Read tag'),
          ),
        ),
        const SizedBox(height: 10),
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
