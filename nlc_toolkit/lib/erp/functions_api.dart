import 'erp_config.dart';
import 'erp_http.dart';
import 'firestore_api.dart' show IdTokenProvider;

/// Fonctions appelables de l'ERP (protocole « callable » de Cloud Functions).
class FunctionsApi {
  FunctionsApi(this._config, this._http, this._idToken);

  final ErpConfig _config;
  final ErpHttp _http;
  final IdTokenProvider _idToken;

  /// Appelle la fonction [name] avec [data] et renvoie son résultat.
  /// Une erreur levée par la fonction devient une [ErpException] qui porte son message.
  Future<Object?> call(String name, [Map<String, Object?>? data]) async {
    final url = Uri.parse('${_config.functionsBase}/$name');
    final response = await _http.postJson(url, {
      'data': data,
    }, bearer: await _idToken());

    final json = response.json;
    final error = erpErrorBody(json);
    if (error != null || !response.ok) {
      final status = error?['status'];
      final message = error?['message'];
      throw ErpException(
        erpFailureFrom(status is String ? status : null, response.status),
        message is String && message.isNotEmpty
            ? message
            : 'La fonction $name a répondu ${response.status}.',
        code: status is String ? status : null,
        httpStatus: response.status,
      );
    }
    return json is Map ? json['result'] : null;
  }
}
