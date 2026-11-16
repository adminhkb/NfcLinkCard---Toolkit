// Bouton de choix du lecteur : « Lecteur externe » (ChameleonUltra) ou
// « NFC du téléphone » (puce native). Visible sur Android quand le téléphone a
// une puce NFC. Toujours affiché en haut de la carte « Appareil », connecté ou
// non, pour pouvoir basculer à tout moment.
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nlc_toolkit/connector/phone_nfc.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/main.dart';

class ReaderSourceChooser extends StatefulWidget {
  const ReaderSourceChooser({super.key});

  @override
  State<ReaderSourceChooser> createState() => _ReaderSourceChooserState();
}

class _ReaderSourceChooserState extends State<ReaderSourceChooser> {
  bool _supported = false;
  bool _busy = false;
  bool _failed = false;

  bool get _platform => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!_platform) return;
    final available = await PhoneNfc.isAvailable();
    if (mounted) setState(() => _supported = available);
  }

  Future<void> _useNative() async {
    final appState = context.read<NlcAppState>();
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final ok = await appState.connectPhoneNfc();
      if (!ok && mounted) setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useExternal() async {
    final appState = context.read<NlcAppState>();
    setState(() => _failed = false);
    await appState.useExternalReader();
  }

  @override
  Widget build(BuildContext context) {
    if (!_platform || !_supported) return const SizedBox.shrink();
    final appState = context.watch<NlcAppState>();
    final french = Localizations.localeOf(context).languageCode == 'fr';
    final native = appState.isPhoneNfc;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Nlc.slate900,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _segment(
                  label: french ? 'Lecteur externe' : 'External reader',
                  icon: Icons.usb_rounded,
                  selected: !native,
                  onTap: (native && !_busy) ? _useExternal : null,
                ),
                _segment(
                  label: french ? 'NFC du téléphone' : 'Phone NFC',
                  icon: Icons.contactless_rounded,
                  selected: native,
                  busy: _busy,
                  onTap: (!native && !_busy) ? _useNative : null,
                ),
              ],
            ),
          ),
          if (native) ...[
            const SizedBox(height: 8),
            Text(
              french
                  ? 'NFC du téléphone actif. Approchez le badge du dos du téléphone.'
                  : 'Phone NFC active. Hold the badge to the back of the phone.',
              style: const TextStyle(color: Nlc.emerald300, fontSize: 12),
            ),
          ],
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              french
                  ? 'NFC indisponible. Activez le NFC dans les réglages Android.'
                  : 'NFC unavailable. Turn on NFC in Android settings.',
              style: const TextStyle(color: Nlc.rose300, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Expanded(
      child: Material(
        color:
            selected ? Nlc.violet500.withValues(alpha: 0.20) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? Nlc.violet200 : Nlc.slate400,
                  ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Nlc.violet200 : Nlc.slate400,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
