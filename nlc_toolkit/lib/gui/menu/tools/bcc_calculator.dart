import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:flutter/material.dart';

class BccCalculatorMenu extends StatefulWidget {
  const BccCalculatorMenu({super.key});

  @override
  State<BccCalculatorMenu> createState() => _BccCalculatorMenuState();
}

class _BccCalculatorMenuState extends State<BccCalculatorMenu> {
  final _uidController = TextEditingController();
  String? _error;
  String? _bcc;

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  void _calculate() {
    final uid = _uidController.text.replaceAll(RegExp(r'[\s:]'), '');
    if (!RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(uid)) {
      setState(() {
        _error = AppLocalizations.of(context)!.bcc_uid_invalid;
        _bcc = null;
      });
      return;
    }

    final bcc = calculateBcc(hexToBytes(uid));
    setState(() {
      _error = null;
      _bcc = bcc.toRadixString(16).padLeft(2, '0').toUpperCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(localizations.bcc_calculator),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _uidController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: localizations.uid,
                hintText: '04 A1 B2 C3',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null || _bcc != null) {
                  setState(() {
                    _error = null;
                    _bcc = null;
                  });
                }
              },
              onSubmitted: (_) => _calculate(),
            ),
            if (_bcc != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                '${localizations.bcc}: $_bcc',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.close),
        ),
        FilledButton(
          onPressed: _calculate,
          child: Text(localizations.bcc_calculate),
        ),
      ],
    );
  }
}
