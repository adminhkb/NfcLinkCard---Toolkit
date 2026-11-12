import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'auth_controller.dart';
import 'firestore_api.dart';
import 'models.dart';
import 'storage_api.dart';

/// Ce qu'il faut pour enregistrer un dump : le contenu lu sur le badge et de quoi le retrouver.
class NewBadgeDump {
  const NewBadgeDump({
    required this.siteId,
    required this.bytes,
    required this.name,
    required this.technology,
    required this.uid,
    required this.tagType,
  });

  /// Immeuble auquel rattacher le dump.
  final String siteId;

  /// Contenu du dump (le badge sérialisé par l'application).
  final Uint8List bytes;
  final String name;
  final BadgeTech technology;
  final String uid;
  final int tagType;
}

/// Enregistre, liste, télécharge et supprime les dumps d'un établissement, à travers Firestore
/// (la référence rattachée à l'immeuble) et Storage (le fichier). Le contenu n'est jamais gardé
/// sur l'appareil : [fetch] le rend le temps d'une copie.
class BadgeDumpRepo {
  BadgeDumpRepo({
    required FirestoreApi firestore,
    required FirebaseStorageApi storage,
    required this.issuerId,
    required this.userId,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _firestore = firestore,
       _storage = storage,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now;

  final FirestoreApi _firestore;
  final FirebaseStorageApi _storage;
  final String issuerId;

  /// Compte connecté, inscrit sur chaque dump enregistré.
  final String userId;
  final Uuid _uuid;
  final DateTime Function() _now;

  String get _collection => 'issuers/$issuerId/badge_dumps';
  String _objectPath(String dumpId) => 'issuers/$issuerId/badge_dumps/$dumpId';

  /// Téléverse le dump puis écrit sa référence rattachée à l'immeuble. Le fichier est envoyé
  /// avant la référence : un lecteur ne voit donc jamais une référence sans fichier. Si l'écriture
  /// de la référence échoue, le fichier tout juste envoyé est retiré pour ne pas rester orphelin.
  Future<BadgeDump> save(NewBadgeDump dump) async {
    final id = _uuid.v4();
    final path = _objectPath(id);
    // Le dump est rangé comme un blob binaire : son contenu est du JSON, mais Storage le traite
    // comme des octets opaques (l'application est seule à le relire et à l'interpréter).
    await _storage.upload(
      path,
      dump.bytes,
      contentType: 'application/octet-stream',
    );
    try {
      final doc = await _firestore.createDocument(_collection, {
        'siteId': dump.siteId,
        'storagePath': path,
        'name': dump.name.trim(),
        'technology': dump.technology.key,
        'uid': dump.uid,
        'tagType': dump.tagType,
        'byteSize': dump.bytes.length,
        'createdAt': _now(),
        'updatedAt': _now(),
        'createdBy': userId,
      }, docId: id);
      return BadgeDump.fromDoc(doc);
    } catch (_) {
      await _deleteObjectQuietly(path);
      rethrow;
    }
  }

  /// Dumps rattachés à l'immeuble [siteId].
  Future<List<BadgeDump>> listForSite(String siteId) async {
    final docs = await _firestore.query(
      'badge_dumps',
      parent: 'issuers/$issuerId',
      where: FieldFilter.equals('siteId', siteId),
    );
    return docs.map(BadgeDump.fromDoc).toList();
  }

  /// Tous les dumps de l'établissement.
  Future<List<BadgeDump>> listAll() async {
    final docs = await _firestore.listDocuments(_collection);
    return docs.map(BadgeDump.fromDoc).toList();
  }

  /// Récupère le contenu d'un dump, le temps d'une copie, sans le conserver.
  Future<Uint8List> fetch(BadgeDump dump) =>
      _storage.download(dump.storagePath);

  /// Supprime la référence puis le fichier. La référence part en premier : le dump disparaît
  /// de la liste même si le fichier résiste.
  Future<void> delete(BadgeDump dump) async {
    await _firestore.deleteDocument('$_collection/${dump.id}');
    await _deleteObjectQuietly(dump.storagePath);
  }

  Future<void> _deleteObjectQuietly(String path) async {
    try {
      await _storage.delete(path);
    } catch (_) {
      // Un fichier qui résiste à la suppression n'empêche pas l'opération d'aboutir : il n'est
      // plus référencé et reste couvert par les règles de sécurité.
    }
  }
}

/// Point d'entrée des dumps pour l'interface : fabrique un dépôt rattaché à l'établissement et au
/// compte actifs. Renvoie `null` tant qu'aucun établissement n'est choisi ou que l'application est
/// hors connexion (un dump ne s'enregistre qu'en ligne).
class BadgeDumps {
  BadgeDumps({
    required FirestoreApi firestore,
    required FirebaseStorageApi storage,
    required AuthController auth,
    DateTime Function()? now,
  }) : _firestore = firestore,
       _storage = storage,
       _auth = auth,
       _now = now;

  final FirestoreApi _firestore;
  final FirebaseStorageApi _storage;
  final AuthController _auth;
  final DateTime Function()? _now;

  bool get available =>
      !_auth.offline && _auth.currentIssuer != null && _auth.user != null;

  BadgeDumpRepo? repo() {
    final issuerId = _auth.currentIssuer?.id;
    final userId = _auth.user?.uid;
    if (_auth.offline || issuerId == null || userId == null) return null;
    return BadgeDumpRepo(
      firestore: _firestore,
      storage: _storage,
      issuerId: issuerId,
      userId: userId,
      now: _now,
    );
  }
}
