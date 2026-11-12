// Libellés, couleurs et formats de l'espace Badges, identiques à ceux de l'ERP.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nlc_toolkit/erp/badge_stats.dart';
import 'package:nlc_toolkit/erp/models.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';

String siteStatusLabel(AppLocalizations l, SiteStatus status) =>
    switch (status) {
      SiteStatus.nouveau => l.nlc_site_status_new,
      SiteStatus.prospecte => l.nlc_site_status_prospected,
      SiteStatus.client => l.nlc_site_status_client,
      SiteStatus.bloque => l.nlc_site_status_blocked,
    };

/// Couleurs des pastilles de la carte de l'ERP.
Color siteStatusColor(SiteStatus status) => switch (status) {
  SiteStatus.nouveau => Nlc.slate400,
  SiteStatus.prospecte => Nlc.amber500,
  SiteStatus.client => Nlc.emerald500,
  SiteStatus.bloque => Nlc.rose500,
};

String siteKindLabel(AppLocalizations l, BadgeSiteKind kind) => switch (kind) {
  BadgeSiteKind.immeuble => l.nlc_site_kind_building,
  BadgeSiteKind.residence => l.nlc_site_kind_residence,
  BadgeSiteKind.parking => l.nlc_site_kind_parking,
  BadgeSiteKind.bureaux => l.nlc_site_kind_offices,
  BadgeSiteKind.maison => l.nlc_site_kind_house,
  BadgeSiteKind.lieuPassage => l.nlc_site_kind_place,
  BadgeSiteKind.autre => l.nlc_site_kind_other,
};

String compatibilityLabel(AppLocalizations l, BadgeCompatibility value) =>
    switch (value) {
      BadgeCompatibility.inconnue => l.nlc_compat_unknown,
      BadgeCompatibility.ok => l.nlc_compat_ok,
      BadgeCompatibility.partielle => l.nlc_compat_partial,
      BadgeCompatibility.ko => l.nlc_compat_ko,
    };

Color compatibilityColor(BadgeCompatibility value) => switch (value) {
  BadgeCompatibility.inconnue => Nlc.slate400,
  BadgeCompatibility.ok => Nlc.emerald400,
  BadgeCompatibility.partielle => Nlc.amber400,
  BadgeCompatibility.ko => Nlc.rose400,
};

String saleStatusLabel(AppLocalizations l, BadgeSaleStatus status) =>
    switch (status) {
      BadgeSaleStatus.demande => l.nlc_sale_status_request,
      BadgeSaleStatus.rdv => l.nlc_sale_status_appointment,
      BadgeSaleStatus.copie => l.nlc_sale_status_copied,
      BadgeSaleStatus.annule => l.nlc_sale_status_cancelled,
    };

Color saleStatusColor(BadgeSaleStatus status) => switch (status) {
  BadgeSaleStatus.demande => Nlc.sky400,
  BadgeSaleStatus.rdv => Nlc.violet400,
  BadgeSaleStatus.copie => Nlc.emerald400,
  BadgeSaleStatus.annule => Nlc.slate400,
};

String techLabel(AppLocalizations l, BadgeTech tech) =>
    tech == BadgeTech.autre ? l.nlc_other : tech.shortLabel;

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// « 20,00 € »
String formatEuro(BuildContext context, double amount) =>
    NumberFormat.currency(locale: _locale(context), symbol: '€').format(amount);

/// « 14:32 »
String formatTime(BuildContext context, DateTime time) =>
    DateFormat.Hm(_locale(context)).format(time);

/// « Aujourd'hui · 18:30 », « Demain · 10:00 », sinon « sam. 14 nov. · 18:30 ».
String appointmentLabel(
  BuildContext context,
  AppLocalizations l,
  int? when,
  int now,
) {
  if (when == null) return l.nlc_date_to_set;
  final date = DateTime.fromMillisecondsSinceEpoch(when);
  final time = formatTime(context, date);
  final days = daysBetween(now, when);
  if (days == 0) return '${l.nlc_today} · $time';
  if (days == 1) return '${l.nlc_tomorrow} · $time';
  return '${DateFormat('EEE d MMM', _locale(context)).format(date)} · $time';
}

/// Un rendez-vous est en retard une heure après l'heure prévue, comme dans l'ERP.
bool isLate(int? when, int now) => when != null && when < now - 3600000;

/// Itinéraire Google Maps vers un point, dans le navigateur.
Uri directionsUrl(double lat, double lng) => Uri.parse(
  'https://www.google.com/maps/dir/?api=1&destination=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
);
