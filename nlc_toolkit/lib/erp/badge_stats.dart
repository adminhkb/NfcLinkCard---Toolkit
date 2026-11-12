// Indicateurs de l'espace Badges utiles sur le terrain : statut de chaque immeuble, rendez-vous à
// venir et compteurs. Mêmes règles que l'ERP (src/utils/badgeStats.ts), sans les calculs financiers
// qui restent dans l'ERP.
import 'models.dart';

/// Données Badges d'un établissement, lues à un instant donné.
class BadgeSnapshot {
  const BadgeSnapshot({
    required this.sites,
    required this.sales,
    required this.actions,
    required this.loadedAt,
  });

  final List<BadgeSite> sites;
  final List<BadgeSale> sales;
  final List<BadgeAction> actions;
  final DateTime loadedAt;

  static final empty = BadgeSnapshot(
    sites: const [],
    sales: const [],
    actions: const [],
    loadedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class SiteSummary {
  const SiteSummary({
    required this.status,
    required this.actions,
    required this.activePosters,
    required this.contacts,
    required this.openLeads,
    required this.copies,
    required this.badges,
    required this.broughtContacts,
    required this.broughtCopies,
    required this.broughtBadges,
    required this.lastCopyDate,
  });

  final SiteStatus status;
  final int actions;

  /// Affiches encore en place.
  final int activePosters;
  final int contacts;

  /// Demandes et rendez-vous en cours.
  final int openLeads;
  final int copies;
  final int badges;

  // Lieu de passage : ce que ses affiches ont amené (chaque copie reste rangée dans l'immeuble du client).
  final int broughtContacts;
  final int broughtCopies;
  final int broughtBadges;
  final int? lastCopyDate;
}

const _dayMs = 86400000;

int startOfDay(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

/// Nombre de jours calendaires entre deux dates (insensible au changement d'heure).
int daysBetween(int from, int to) =>
    ((startOfDay(to) - startOfDay(from)) / _dayMs).round();

SiteSummary computeSiteSummary(
  BadgeSite site,
  List<BadgeAction> actions,
  List<BadgeSale> sales,
) {
  final siteActions = actions.where((a) => a.siteId == site.id).toList();
  final siteSales = sales.where((s) => s.siteId == site.id).toList();
  final done = siteSales.where((s) => s.isDone).toList();
  final brought = sales
      .where((s) => s.source == 'lieu_passage' && s.sourceSiteId == site.id)
      .toList();
  final broughtDone = brought.where((s) => s.isDone).toList();

  var status = SiteStatus.nouveau;
  if (site.doNotProspect || site.compatibility == BadgeCompatibility.ko) {
    status = SiteStatus.bloque;
  } else if (done.isNotEmpty || broughtDone.isNotEmpty) {
    status = SiteStatus.client;
  } else if (siteActions.isNotEmpty ||
      siteSales.isNotEmpty ||
      brought.isNotEmpty) {
    status = SiteStatus.prospecte;
  }

  int? lastCopy;
  for (final sale in done) {
    final date = sale.copyDate ?? sale.contactDate;
    if (lastCopy == null || date > lastCopy) lastCopy = date;
  }

  int badges(Iterable<BadgeSale> list) =>
      list.fold(0, (total, s) => total + s.quantity);

  return SiteSummary(
    status: status,
    actions: siteActions.length,
    activePosters: siteActions
        .where((a) => a.type == 'affiche' && a.removedAt == null)
        .length,
    contacts: siteSales.length,
    openLeads: siteSales
        .where(
          (s) =>
              s.status == BadgeSaleStatus.demande ||
              s.status == BadgeSaleStatus.rdv,
        )
        .length,
    copies: done.length,
    badges: badges(done),
    broughtContacts: brought.length,
    broughtCopies: broughtDone.length,
    broughtBadges: badges(broughtDone),
    lastCopyDate: lastCopy,
  );
}

/// Vue d'ensemble calculée à partir d'un [BadgeSnapshot].
class BadgeOverview {
  BadgeOverview._({
    required this.sites,
    required this.upcoming,
    required this.requests,
    required this.pipeline,
    required this.badgesCopied,
    required this.monthBadges,
    required this.monthCopies,
  });

  /// Indicateurs par identifiant d'immeuble.
  final Map<String, SiteSummary> sites;

  /// Rendez-vous fixés, du plus ancien au plus lointain.
  final List<BadgeSale> upcoming;

  /// Demandes reçues qui attendent un rendez-vous, de la plus ancienne à la plus récente.
  final List<BadgeSale> requests;
  final Map<BadgeSaleStatus, int> pipeline;
  final int badgesCopied;

  /// Badges et copies du mois en cours.
  final int monthBadges;
  final int monthCopies;

  factory BadgeOverview.compute(BadgeSnapshot data, int now) {
    final pipeline = {for (final status in BadgeSaleStatus.values) status: 0};
    for (final sale in data.sales) {
      pipeline[sale.status] = pipeline[sale.status]! + 1;
    }

    // Même ordre que l'ERP : un rendez-vous sans date est classé à la date du premier contact.
    final upcoming =
        data.sales.where((s) => s.status == BadgeSaleStatus.rdv).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final requests =
        data.sales.where((s) => s.status == BadgeSaleStatus.demande).toList()
          ..sort((a, b) => a.contactDate.compareTo(b.contactDate));

    final today = DateTime.fromMillisecondsSinceEpoch(now);
    final monthStart = DateTime(today.year, today.month).millisecondsSinceEpoch;
    final monthEnd = DateTime(
      today.year,
      today.month + 1,
    ).millisecondsSinceEpoch;
    final done = data.sales.where((s) => s.isDone).toList();
    final ofMonth = done
        .where((s) => s.date >= monthStart && s.date < monthEnd)
        .toList();

    return BadgeOverview._(
      sites: {
        for (final site in data.sites)
          site.id: computeSiteSummary(site, data.actions, data.sales),
      },
      upcoming: upcoming,
      requests: requests,
      pipeline: pipeline,
      badgesCopied: done.fold(0, (total, s) => total + s.quantity),
      monthBadges: ofMonth.fold(0, (total, s) => total + s.quantity),
      monthCopies: ofMonth.length,
    );
  }
}
