import 'package:flutter/foundation.dart';

import 'auth_controller.dart';
import 'badge_stats.dart';
import 'erp_directory.dart';
import 'erp_http.dart';

/// Données Badges de l'établissement actif, rechargées quand il change.
class BadgeController extends ChangeNotifier {
  BadgeController(this._directory, this._auth, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final ErpDirectory _directory;
  final AuthController _auth;
  final DateTime Function() _now;

  String? _issuerId;
  BadgeSnapshot? _data;
  BadgeOverview? _overview;
  ErpException? _error;
  bool _loading = false;
  int _request = 0;
  bool _disposed = false;

  /// Dernières données lues, ou `null` tant que rien n'a été chargé pour cet établissement.
  BadgeSnapshot? get data => _data;
  BadgeOverview? get overview => _overview;

  /// Échec du dernier chargement. Les données précédentes, s'il y en a, restent affichées.
  ErpException? get error => _error;
  bool get loading => _loading;

  /// L'ERP est joignable et un établissement est choisi.
  bool get available => _issuerId != null;

  void _onAuthChanged() {
    final issuerId = _auth.stage == AuthStage.ready && !_auth.offline
        ? _auth.currentIssuer?.id
        : null;
    if (issuerId == _issuerId) return;
    _issuerId = issuerId;
    _data = null;
    _overview = null;
    _error = null;
    _request += 1;
    _loading = false;
    if (issuerId == null) {
      _notify();
    } else {
      refresh();
    }
  }

  /// Relit les données de l'établissement actif.
  Future<void> refresh() async {
    final issuerId = _issuerId;
    if (issuerId == null) return;
    final request = ++_request;
    _loading = true;
    _notify();
    try {
      final snapshot = await _directory.loadBadges(issuerId);
      if (request != _request) return;
      _data = snapshot;
      _overview = BadgeOverview.compute(
        snapshot,
        _now().millisecondsSinceEpoch,
      );
      _error = null;
    } on ErpException catch (error) {
      if (request != _request) return;
      _error = error;
    }
    _loading = false;
    _notify();
  }

  /// Recalcule les indicateurs qui dépendent de l'heure (rendez-vous en retard, mois en cours).
  void recompute() {
    final snapshot = _data;
    if (snapshot == null) return;
    _overview = BadgeOverview.compute(snapshot, _now().millisecondsSinceEpoch);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
