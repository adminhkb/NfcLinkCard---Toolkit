// Modèle de l'espace Badges de l'ERP, tel qu'il est enregistré dans Firestore sous
// issuers/{issuerId}/badge_sites, badge_sales et badge_actions.
//
// La lecture suit les mêmes règles que l'ERP (src/components/badges/badgeStore.ts) : une valeur
// absente ou inattendue est remplacée par la même valeur par défaut, pour que les deux applications
// affichent toujours la même chose. Les dates sont en millisecondes depuis 1970.
import 'firestore_api.dart';

/// Établissement de l'ERP auquel le compte a accès.
class Issuer {
  const Issuer({
    required this.id,
    required this.name,
    this.siret = '',
    this.colorTheme = 'indigo',
  });

  final String id;
  final String name;
  final String siret;

  /// Couleur d'accent choisie dans l'ERP : `indigo`, `emerald`, `blue`, `violet` ou `rose`.
  final String colorTheme;

  /// Champs lus dans la fiche de l'établissement. Les autres (SMTP, clés d'API, coordonnées
  /// bancaires) ne sont jamais demandés.
  static const fields = ['name', 'siret', 'colorTheme'];

  factory Issuer.fromDoc(FirestoreDoc doc) => Issuer(
    id: doc.id,
    name: _text(doc.data['name']).trim(),
    siret: _text(doc.data['siret']).trim(),
    colorTheme: _text(doc.data['colorTheme']).isEmpty
        ? 'indigo'
        : _text(doc.data['colorTheme']),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'siret': siret,
    'colorTheme': colorTheme,
  };

  static Issuer? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['name'] is! String) {
      return null;
    }
    return Issuer(
      id: json['id'] as String,
      name: json['name'] as String,
      siret: _text(json['siret']),
      colorTheme: _text(json['colorTheme']).isEmpty
          ? 'indigo'
          : _text(json['colorTheme']),
    );
  }
}

enum BadgeTech {
  mifareUid('mifare_uid', '13,56 MHz UID'),
  mifareCuid('mifare_cuid', '13,56 MHz CUID'),
  emT5577('em_t5577', '125 kHz'),
  autre('autre', 'Autre');

  const BadgeTech(this.key, this.shortLabel);
  final String key;
  final String shortLabel;
}

enum BadgeSiteKind {
  immeuble('immeuble', 'Immeuble'),
  residence('residence', 'Résidence'),
  parking('parking', 'Parking'),
  bureaux('bureaux', 'Bureaux'),
  maison('maison', 'Maison'),
  lieuPassage('lieu_passage', 'Lieu de passage'),
  autre('autre', 'Autre lieu');

  const BadgeSiteKind(this.key, this.label);
  final String key;
  final String label;
}

enum BadgeCompatibility {
  inconnue('inconnue', 'Pas encore testé'),
  ok('ok', 'Copiable'),
  partielle('partielle', 'Anti-copie (CUID/FUID requis)'),
  ko('ko', 'Non copiable');

  const BadgeCompatibility(this.key, this.label);
  final String key;
  final String label;
}

enum BadgeSaleStatus {
  demande('demande', 'Demande reçue'),
  rdv('rdv', 'RDV fixé'),
  copie('copie', 'Copié'),
  annule('annule', 'Annulé');

  const BadgeSaleStatus(this.key, this.label);
  final String key;
  final String label;
}

/// Statut d'un immeuble, déduit de sa prospection et de ses copies.
enum SiteStatus {
  nouveau('À prospecter'),
  prospecte('Prospecté'),
  client('Clients'),
  bloque('Bloqué');

  const SiteStatus(this.label);
  final String label;
}

class BadgeSite {
  const BadgeSite({
    required this.id,
    required this.name,
    this.address = '',
    this.city = '',
    this.postcode = '',
    this.lat,
    this.lng,
    this.kind = BadgeSiteKind.immeuble,
    this.units,
    this.accessSystem = '',
    this.compatibility = BadgeCompatibility.inconnue,
    this.doNotProspect = false,
    this.notes = '',
  });

  final String id;
  final String name;
  final String address;
  final String city;
  final String postcode;
  final double? lat;
  final double? lng;
  final BadgeSiteKind kind;

  /// Logements ou boîtes aux lettres.
  final int? units;

  /// Marque du système d'accès (Intratone, Hexact, Vigik…).
  final String accessSystem;
  final BadgeCompatibility compatibility;
  final bool doNotProspect;
  final String notes;

  /// Lieu où des gens voient l'affiche sans y habiter (commerce, lieu de travail…).
  bool get isPlace => kind == BadgeSiteKind.lieuPassage;
  bool get hasPosition => lat != null && lng != null;

  factory BadgeSite.fromDoc(FirestoreDoc doc) {
    final d = doc.data;
    return BadgeSite(
      id: doc.id,
      name: _text(d['name']),
      address: _text(d['address']),
      city: _text(d['city']),
      postcode: _text(d['postcode']),
      lat: _numOrNull(d['lat']),
      lng: _numOrNull(d['lng']),
      kind: _oneOf(
        d['kind'],
        BadgeSiteKind.values,
        (v) => v.key,
        BadgeSiteKind.immeuble,
      ),
      units: _numOrNull(d['units'])?.round(),
      accessSystem: _text(d['accessSystem']),
      compatibility: _oneOf(
        d['compatibility'],
        BadgeCompatibility.values,
        (v) => v.key,
        BadgeCompatibility.inconnue,
      ),
      doNotProspect: d['doNotProspect'] == true,
      notes: _text(d['notes']),
    );
  }
}

class BadgeAction {
  const BadgeAction({
    required this.id,
    required this.siteId,
    required this.type,
    required this.date,
    this.quantity = 1,
    this.removedAt,
  });

  final String id;

  /// Vide pour une publication générale sur les réseaux sociaux.
  final String siteId;

  /// `affiche`, `flyer_bal`, `porte_a_porte`, `reseaux_sociaux` ou `autre`.
  final String type;
  final int date;
  final int quantity;

  /// Affiche retirée ou disparue.
  final int? removedAt;

  static const _types = [
    'affiche',
    'flyer_bal',
    'porte_a_porte',
    'reseaux_sociaux',
    'autre',
  ];

  factory BadgeAction.fromDoc(FirestoreDoc doc, {required int now}) {
    final d = doc.data;
    final type = _text(d['type']);
    return BadgeAction(
      id: doc.id,
      siteId: _text(d['siteId']),
      // « gardien » n'est plus proposé par l'ERP : ces actions passent en « autre ».
      type: type == 'gardien'
          ? 'autre'
          : (_types.contains(type) ? type : 'affiche'),
      date: _toMs(d['date']) ?? _toMs(d['createdAt']) ?? now,
      quantity: _num(d['quantity'], 1).round(),
      removedAt: _toMs(d['removedAt']),
    );
  }
}

class BadgeSale {
  const BadgeSale({
    required this.id,
    required this.status,
    required this.contactDate,
    this.siteId,
    this.source = 'autre',
    this.sourceSiteId,
    this.customerName = '',
    this.customerPhone = '',
    this.customerDetail = '',
    this.appointmentDate,
    this.copyDate,
    this.quantity = 1,
    this.failedCount = 0,
    this.technology = BadgeTech.mifareUid,
    this.price = 0,
    this.paid = true,
    this.atHome = false,
    this.notes = '',
  });

  final String id;

  /// Immeuble où le badge du client fonctionne.
  final String? siteId;
  final BadgeSaleStatus status;
  final String source;

  /// Lieu de passage où le client a vu l'affiche (source « lieu_passage »).
  final String? sourceSiteId;
  final String customerName;
  final String customerPhone;

  /// Appartement, étage…
  final String customerDetail;
  final int contactDate;
  final int? appointmentDate;
  final int? copyDate;

  /// Badges remis au client.
  final int quantity;
  final int failedCount;
  final BadgeTech technology;

  /// Montant total payé par le client.
  final double price;
  final bool paid;
  final bool atHome;
  final String notes;

  bool get isDone => status == BadgeSaleStatus.copie;

  /// Date qui situe la vente : la copie, sinon le rendez-vous, sinon le premier contact.
  int get date => switch (status) {
    BadgeSaleStatus.copie => copyDate ?? contactDate,
    BadgeSaleStatus.rdv => appointmentDate ?? contactDate,
    _ => contactDate,
  };

  factory BadgeSale.fromDoc(FirestoreDoc doc, {required int now}) {
    final d = doc.data;
    final siteId = _text(d['siteId']);
    final sourceSiteId = _text(d['sourceSiteId']);
    return BadgeSale(
      id: doc.id,
      siteId: siteId.isEmpty ? null : siteId,
      status: _oneOf(
        d['status'],
        BadgeSaleStatus.values,
        (v) => v.key,
        BadgeSaleStatus.copie,
      ),
      source: _text(d['source']).isEmpty ? 'autre' : _text(d['source']),
      sourceSiteId: sourceSiteId.isEmpty ? null : sourceSiteId,
      customerName: _text(d['customerName']),
      customerPhone: _text(d['customerPhone']),
      customerDetail: _text(d['customerDetail']),
      contactDate: _toMs(d['contactDate']) ?? _toMs(d['createdAt']) ?? now,
      appointmentDate: _toMs(d['appointmentDate']),
      copyDate: _toMs(d['copyDate']),
      quantity: _num(d['quantity'], 1).round(),
      failedCount: _num(d['failedCount'], 0).round(),
      technology: _oneOf(
        d['technology'],
        BadgeTech.values,
        (v) => v.key,
        BadgeTech.mifareUid,
      ),
      price: _num(d['price'], 0).toDouble(),
      paid: d['paid'] != false,
      atHome: d['atHome'] == true,
      notes: _text(d['notes']),
    );
  }
}

/// Dump d'un badge enregistré dans Firebase Storage et rattaché à un immeuble.
///
/// Rangé sous issuers/{issuerId}/badge_dumps/{id} (référence) et dans le bucket à
/// [storagePath] (le fichier lui-même). Le dump n'est jamais gardé sur l'appareil : il est
/// téléchargé le temps d'une copie, puis oublié.
class BadgeDump {
  const BadgeDump({
    required this.id,
    required this.siteId,
    required this.storagePath,
    this.name = '',
    this.technology = BadgeTech.mifareUid,
    this.uid = '',
    this.tagType = 0,
    this.byteSize = 0,
    this.createdAt,
    this.createdBy = '',
  });

  final String id;

  /// Immeuble auquel le dump est rattaché (issuers/{issuerId}/badge_sites/{siteId}).
  final String siteId;

  /// Chemin complet du fichier dans le bucket.
  final String storagePath;

  /// Nom lisible (nom du badge ou de l'immeuble).
  final String name;
  final BadgeTech technology;

  /// UID du badge en hexadécimal, pour l'afficher sans ouvrir le fichier.
  final String uid;

  /// Type de puce (valeur interne à l'application), pour reconstruire le badge à la copie.
  final int tagType;

  /// Taille du fichier en octets.
  final int byteSize;
  final int? createdAt;

  /// UID du compte qui a enregistré le dump.
  final String createdBy;

  factory BadgeDump.fromDoc(FirestoreDoc doc) {
    final d = doc.data;
    return BadgeDump(
      id: doc.id,
      siteId: _text(d['siteId']),
      storagePath: _text(d['storagePath']),
      name: _text(d['name']),
      technology: _oneOf(
        d['technology'],
        BadgeTech.values,
        (v) => v.key,
        BadgeTech.mifareUid,
      ),
      uid: _text(d['uid']),
      tagType: _num(d['tagType'], 0).round(),
      byteSize: _num(d['byteSize'], 0).round(),
      createdAt: _toMs(d['createdAt']),
      createdBy: _text(d['createdBy']),
    );
  }
}

/* ─────────────── Lecture tolérante des valeurs ─────────────── */

String _text(Object? value) => value is String ? value : '';

num _num(Object? value, num fallback) =>
    value is num && value.isFinite ? value : fallback;

double? _numOrNull(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

T _oneOf<T>(
  Object? value,
  List<T> allowed,
  String Function(T) key,
  T fallback,
) {
  for (final candidate in allowed) {
    if (key(candidate) == value) return candidate;
  }
  return fallback;
}

/// Date enregistrée comme horodatage Firestore, nombre de millisecondes ou texte ISO.
int? _toMs(Object? value) {
  if (value == null || value == '') return null;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is num) return value.isFinite ? value.round() : null;
  if (value is String) return DateTime.tryParse(value)?.millisecondsSinceEpoch;
  return null;
}
