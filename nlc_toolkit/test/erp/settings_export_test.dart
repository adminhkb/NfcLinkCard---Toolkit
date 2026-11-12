// Les réglages exportés (fichier ou QR code) ne doivent jamais emporter la session ERP.
import 'package:flutter_test/flutter_test.dart';
import 'package:nlc_toolkit/sharedprefsprovider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('l\'export des réglages ne contient jamais la session ERP, et l\'import ne peut pas en injecter', () async {
    SharedPreferences.setMockInitialValues({
      'debug': true,
      'erp_secret_session': 'plain:c2VjcmV0',
      'erp_active_issuer_id': 'abc',
      'mct_bundled_dictionaries_seeded_v1': true,
    });
    final provider = SharedPreferencesProvider();
    await provider.load();

    final exported = provider.dumpSettingsToJson();
    expect(exported, contains('"debug":true'));
    expect(exported, isNot(contains('erp_')));
    expect(exported, isNot(contains('c2VjcmV0')));

    provider.restoreSettingsFromJson(
      '{"confirm_delete":false,"erp_secret_session":"plain:cGlyYXRl"}',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('confirm_delete'), isFalse);
    expect(prefs.getString('erp_secret_session'), 'plain:c2VjcmV0');
  });
}
