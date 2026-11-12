import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rangement des secrets de la session (jeton de renouvellement, jeton d'appareil mémorisé).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Rangement en mémoire : tests et mode démonstration.
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Chiffre un secret avant de l'écrire sur le disque.
abstract class SecretProtector {
  /// Préfixe qui indique, dans la valeur enregistrée, comment elle a été protégée.
  String get scheme;
  Uint8List protect(Uint8List clear);

  /// Renvoie `null` si la valeur ne peut pas être relue (autre compte, autre machine, fichier altéré).
  Uint8List? unprotect(Uint8List stored);
}

/// Aucune protection supplémentaire : la valeur reste dans le stockage privé de l'application.
class PlainProtector implements SecretProtector {
  const PlainProtector();

  @override
  String get scheme => 'plain';

  @override
  Uint8List protect(Uint8List clear) => clear;

  @override
  Uint8List? unprotect(Uint8List stored) => stored;
}

/// Préfixe des clés réservées à la liaison ERP dans les préférences.
/// Ces clés ne sont ni exportées ni importées avec les réglages.
const erpPreferencePrefix = 'erp_';

/// Secrets rangés dans les préférences de l'application, chiffrés par [protector].
///
/// Sous Windows, le chiffrement est celui du compte Windows (DPAPI) : le fichier recopié sur une
/// autre session ou une autre machine est illisible.
class PrefsSecretStore implements SecretStore {
  PrefsSecretStore(this._prefs, {SecretProtector? protector})
    : _protector = protector ?? defaultSecretProtector();

  final SharedPreferences _prefs;
  final SecretProtector _protector;

  String _name(String key) => '${erpPreferencePrefix}secret_$key';

  @override
  Future<String?> read(String key) async {
    final stored = _prefs.getString(_name(key));
    if (stored == null) return null;
    final separator = stored.indexOf(':');
    if (separator < 0 || stored.substring(0, separator) != _protector.scheme) {
      return null;
    }
    try {
      final clear = _protector.unprotect(
        base64Decode(stored.substring(separator + 1)),
      );
      return clear == null ? null : utf8.decode(clear);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final protected = _protector.protect(
      Uint8List.fromList(utf8.encode(value)),
    );
    await _prefs.setString(
      _name(key),
      '${_protector.scheme}:${base64Encode(protected)}',
    );
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(_name(key));
  }
}

SecretProtector defaultSecretProtector() =>
    Platform.isWindows ? DpapiProtector() : const PlainProtector();

/* ─────────────── Windows : API de protection des données (DPAPI) ─────────────── */

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Void> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Void> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);

/// Chiffrement lié au compte Windows de l'utilisateur.
class DpapiProtector implements SecretProtector {
  DpapiProtector() {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    _protect = crypt32.lookupFunction<_CryptNative, _CryptDart>(
      'CryptProtectData',
    );
    _unprotect = crypt32.lookupFunction<_CryptNative, _CryptDart>(
      'CryptUnprotectData',
    );
    _localFree = kernel32
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('LocalFree');
  }

  late final _CryptDart _protect;
  late final _CryptDart _unprotect;
  late final Pointer<Void> Function(Pointer<Void>) _localFree;

  /// Aucune fenêtre ne doit s'ouvrir pendant l'opération.
  static const _uiForbidden = 0x1;

  /// Données mêlées au chiffrement : un secret protégé pour un autre usage ne se relit pas ici.
  static final _entropy = Uint8List.fromList(
    utf8.encode('nlc-toolkit/erp-session/v1'),
  );

  @override
  String get scheme => 'dpapi';

  @override
  Uint8List protect(Uint8List clear) {
    final result = _run(_protect, clear);
    if (result == null) {
      throw StateError('Windows a refusé de chiffrer la session.');
    }
    return result;
  }

  @override
  Uint8List? unprotect(Uint8List stored) => _run(_unprotect, stored);

  Uint8List? _run(_CryptDart operation, Uint8List input) {
    return using((arena) {
      final dataIn = _blob(arena, input);
      final entropy = _blob(arena, _entropy);
      final dataOut = arena<_DataBlob>();
      dataOut.ref
        ..cbData = 0
        ..pbData = nullptr;

      final ok = operation(
        dataIn,
        nullptr,
        entropy,
        nullptr,
        nullptr,
        _uiForbidden,
        dataOut,
      );
      if (ok == 0 || dataOut.ref.pbData == nullptr) return null;
      try {
        return Uint8List.fromList(
          dataOut.ref.pbData.asTypedList(dataOut.ref.cbData),
        );
      } finally {
        _localFree(dataOut.ref.pbData.cast());
      }
    });
  }

  Pointer<_DataBlob> _blob(Arena arena, Uint8List bytes) {
    final buffer = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    final blob = arena<_DataBlob>();
    blob.ref
      ..cbData = bytes.length
      ..pbData = buffer;
    return blob;
  }
}
