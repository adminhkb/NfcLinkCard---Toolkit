import 'badge_stats.dart';
import 'erp_http.dart';
import 'firestore_api.dart';
import 'models.dart';

/// Ce que l'ERP sait du compte connecté.
class AccountProfile {
  const AccountProfile({
    required this.allowed,
    required this.isAdmin,
    required this.issuers,
  });

  /// Le compte a le droit d'utiliser l'ERP, donc le toolkit.
  final bool allowed;

  /// Membre de l'équipe : accès à tous les établissements.
  final bool isAdmin;

  /// Établissements auxquels le compte a accès, triés par nom.
  final List<Issuer> issuers;
}

/// Lecture de l'ERP : droits du compte, établissements et données de l'espace Badges.
class ErpDirectory {
  ErpDirectory(this._firestore, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final FirestoreApi _firestore;
  final DateTime Function() _now;

  /// Applique la règle d'accès de l'ERP : le compte est accepté s'il possède un établissement,
  /// s'il figure parmi les administrateurs autorisés d'un établissement, ou s'il fait partie de
  /// l'équipe (`users/{uid}.isAdmin`).
  Future<AccountProfile> loadProfile(String uid) async {
    final userDoc = await _firestore.getDocument(
      'users/$uid',
      fields: const ['isAdmin', 'isSuperAdmin'],
    );
    final isAdmin = userDoc?.data['isAdmin'] == true;
    final seesEverything = isAdmin || userDoc?.data['isSuperAdmin'] == true;

    if (seesEverything) {
      try {
        final all = await _firestore.listDocuments(
          'issuers',
          fields: Issuer.fields,
        );
        return AccountProfile(
          allowed: true,
          isAdmin: isAdmin,
          issuers: _named(all),
        );
      } on ErpException catch (error) {
        // Les règles de sécurité ont le dernier mot : sans droit de tout lister, on retombe
        // sur les établissements du compte.
        if (error.kind != ErpFailure.permissionDenied) rethrow;
      }
    }

    final own = await _firestore.getDocument(
      'issuers/$uid',
      fields: Issuer.fields,
    );
    final shared = await _firestore.query(
      'issuers',
      where: FieldFilter.arrayContains('allowedAdmins', uid),
      fields: Issuer.fields,
    );
    return AccountProfile(
      allowed: own != null || shared.isNotEmpty || isAdmin,
      isAdmin: isAdmin,
      issuers: _named([?own, ...shared]),
    );
  }

  /// Lit les immeubles, les copies et la prospection de l'établissement [issuerId].
  Future<BadgeSnapshot> loadBadges(String issuerId) async {
    final now = _now();
    final root = 'issuers/$issuerId';
    // Future.wait relaie telle quelle la première erreur (réseau, droits) à l'appelant.
    final [sites, sales, actions] = await Future.wait([
      _firestore.listDocuments('$root/badge_sites'),
      _firestore.listDocuments('$root/badge_sales'),
      _firestore.listDocuments('$root/badge_actions'),
    ]);
    final ms = now.millisecondsSinceEpoch;
    return BadgeSnapshot(
      sites: sites.map(BadgeSite.fromDoc).toList(),
      sales: [for (final doc in sales) BadgeSale.fromDoc(doc, now: ms)],
      actions: [for (final doc in actions) BadgeAction.fromDoc(doc, now: ms)],
      loadedAt: now,
    );
  }

  /// Les fiches sans nom sont des brouillons que l'ERP n'affiche pas non plus.
  List<Issuer> _named(List<FirestoreDoc> docs) {
    final byId = <String, Issuer>{};
    for (final doc in docs) {
      final issuer = Issuer.fromDoc(doc);
      if (issuer.name.isNotEmpty) byId.putIfAbsent(issuer.id, () => issuer);
    }
    return byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
