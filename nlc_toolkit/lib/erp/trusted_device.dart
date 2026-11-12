// Appareil mémorisé de la double authentification (« Se souvenir de cet appareil pendant 30 jours »).
//
// Même mécanisme que dans le navigateur (ERP, src/utils/trustedDevice.ts) : après un code valide, le
// serveur délivre un identifiant d'appareil et un jeton. L'application les garde, chiffrés, et les
// présente à la fonction checkTrustedDevice à chaque ouverture. Seul le serveur décide si le jeton
// est valide, expiré ou révoqué.
import 'dart:convert';

import 'secret_store.dart';

const trustedDeviceDays = 30;

final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
final _deviceIdPattern = RegExp(r'^[A-Za-z0-9]{20}$');

class TrustedDevice {
  const TrustedDevice({
    required this.deviceId,
    required this.token,
    required this.expiresAt,
  });

  final String deviceId;
  final String token;

  /// Fin de validité annoncée par le serveur, en millisecondes.
  final int expiresAt;

  bool isExpiredAt(int now) => expiresAt <= now;

  /// Valide un appareil reçu du serveur ou relu du stockage local.
  static TrustedDevice? parse(Object? value) {
    if (value is! Map) return null;
    final deviceId = value['deviceId'];
    final token = value['token'];
    final expiresAt = value['expiresAt'];
    if (deviceId is! String || !_deviceIdPattern.hasMatch(deviceId)) {
      return null;
    }
    if (token is! String || !_tokenPattern.hasMatch(token)) return null;
    if (expiresAt is! num || !expiresAt.isFinite) return null;
    return TrustedDevice(
      deviceId: deviceId,
      token: token,
      expiresAt: expiresAt.round(),
    );
  }

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'token': token,
    'expiresAt': expiresAt,
  };
}

/// Pourquoi la mémorisation de cet appareil ne vaut plus, affiché sur l'écran du code.
enum TrustNotice { expired, revoked }

class TrustVerdict {
  const TrustVerdict({
    required this.trusted,
    required this.forget,
    this.notice,
  });

  final bool trusted;

  /// La réponse est définitive : le jeton local doit être effacé.
  final bool forget;
  final TrustNotice? notice;
}

/// Traduit la réponse de la fonction checkTrustedDevice.
/// Une réponse inattendue n'efface rien : le code est demandé cette fois-ci et le jeton sera revérifié.
TrustVerdict interpretTrustCheck(Object? response) {
  final data = response is Map ? response : null;
  if (data?['trusted'] == true) {
    return const TrustVerdict(trusted: true, forget: false);
  }
  if (data?['trusted'] == false) {
    return switch (data?['reason']) {
      'expired' => const TrustVerdict(
        trusted: false,
        forget: true,
        notice: TrustNotice.expired,
      ),
      'unknown' => const TrustVerdict(
        trusted: false,
        forget: true,
        notice: TrustNotice.revoked,
      ),
      _ => const TrustVerdict(trusted: false, forget: true),
    };
  }
  return const TrustVerdict(trusted: false, forget: false);
}

/// Rangement chiffré de l'appareil mémorisé, par compte.
class TrustedDeviceStore {
  TrustedDeviceStore(this._secrets);

  final SecretStore _secrets;

  String _key(String uid) => 'trusted_device_$uid';

  Future<TrustedDevice?> load(String uid) async {
    final raw = await _secrets.read(_key(uid));
    if (raw == null) return null;
    try {
      return TrustedDevice.parse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(String uid, TrustedDevice device) =>
      _secrets.write(_key(uid), jsonEncode(device.toJson()));

  Future<void> forget(String uid) => _secrets.delete(_key(uid));
}
