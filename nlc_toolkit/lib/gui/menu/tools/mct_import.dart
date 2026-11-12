import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/helpers/card_save_converters.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:provider/provider.dart';

class _MctFileOutcome {
  final String fileName;
  final MctImportResult? result;
  final String? error;

  const _MctFileOutcome.imported(this.fileName, MctImportResult this.result)
    : error = null;

  const _MctFileOutcome.failed(this.fileName, String this.error)
    : result = null;
}

/// Imports one or more MIFARE Classic Tool text dumps into the library.
class MctImportMenu extends StatefulWidget {
  const MctImportMenu({super.key});

  @override
  State<MctImportMenu> createState() => _MctImportMenuState();
}

class _MctImportMenuState extends State<MctImportMenu> {
  final _outcomes = <_MctFileOutcome>[];
  bool _busy = false;

  Future<void> _pickAndImport() async {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.read<NlcAppState>();
    setState(() => _busy = true);
    try {
      // Any file type: MCT dumps are often saved without the .mct extension,
      // and mobile pickers cannot filter on it.
      final files = await FilePicker.pickFiles(
        dialogTitle: localizations.mct_import,
      );
      if (files.isEmpty) return;

      final outcomes = <_MctFileOutcome>[];
      final imported = <MctImportResult>[];
      for (final file in files) {
        String text;
        try {
          text = utf8.decode(await file.readAsBytes());
        } catch (_) {
          outcomes.add(
            _MctFileOutcome.failed(
              file.name,
              localizations.mct_import_read_error,
            ),
          );
          continue;
        }
        try {
          final result = parseMctDump(text.replaceFirst('﻿', ''));
          final dot = file.name.lastIndexOf('.');
          result.card.name = dot > 0 ? file.name.substring(0, dot) : file.name;
          imported.add(result);
          outcomes.add(_MctFileOutcome.imported(file.name, result));
        } on FormatException catch (error) {
          outcomes.add(
            _MctFileOutcome.failed(
              file.name,
              localizations.mct_import_invalid(error.message),
            ),
          );
        }
      }

      if (imported.isNotEmpty) {
        final cards = appState.sharedPreferencesProvider.getCards();
        cards.addAll(imported.map((result) => result.card));
        appState.sharedPreferencesProvider.setCards(cards);
        appState.changesMade();
      }
      if (mounted) setState(() => _outcomes.insertAll(0, outcomes));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildOutcome(BuildContext context, _MctFileOutcome outcome) {
    final localizations = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final result = outcome.result;
    final details = <String>[];
    if (result != null) {
      details.add(
        localizations.mct_import_card(
          result.card.uid,
          result.sectors.length.toString(),
        ),
      );
      if (result.unreadBlocks > 0) {
        details.add(
          localizations.mct_import_unread(result.unreadBlocks.toString()),
        );
      }
      if (result.partialBlocks > 0) {
        details.add(
          localizations.mct_import_partial(result.partialBlocks.toString()),
        );
      }
    } else {
      details.add(outcome.error!);
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        result != null ? Icons.check_circle_outline : Icons.error_outline,
        color: result != null ? colors.primary : colors.error,
      ),
      title: Text(outcome.fileName, overflow: TextOverflow.ellipsis),
      subtitle: Text(details.join('\n')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final importedCount = _outcomes.where((o) => o.result != null).length;
    return AlertDialog(
      title: Text(localizations.mct_import),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.mct_import_hint),
            if (_outcomes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                localizations.mct_import_imported(importedCount.toString()),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final outcome in _outcomes)
                      _buildOutcome(context, outcome),
                  ],
                ),
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
        FilledButton.icon(
          onPressed: _busy ? null : _pickAndImport,
          icon: const Icon(Icons.upload_file),
          label: Text(localizations.mct_import_choose),
        ),
      ],
    );
  }
}
