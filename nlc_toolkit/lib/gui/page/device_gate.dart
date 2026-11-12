import 'package:flutter/material.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:nlc_toolkit/gui/shell/navigation.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:provider/provider.dart';

/// Affichée à la place d'une fonction qui a besoin du lecteur quand aucun n'est connecté.
class DeviceNeededPage extends StatelessWidget {
  const DeviceNeededPage({
    super.key,
    required this.title,
    this.icon = Icons.nfc_rounded,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NlcPageBody(
        maxWidth: 760,
        children: [
          NlcPageHeader(
            eyebrow: localizations.nlc_nav_device,
            eyebrowIcon: icon,
            title: title,
          ),
          const SizedBox(height: 24),
          NlcCard(
            child: NlcEmptyHint(
              icon: Icons.usb_off_rounded,
              title: localizations.nlc_device_needed_title,
              text: localizations.nlc_device_needed_text,
              action: FilledButton.icon(
                onPressed: () =>
                    context.read<NlcNavigation>().go(NlcDestination.device),
                icon: const Icon(Icons.usb_rounded, size: 18),
                label: Text(localizations.nlc_connect_device),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// N'ouvre la lecture ou l'écriture que si le micrologiciel de l'appareil les prend en charge.
class DeviceIoGate extends StatelessWidget {
  const DeviceIoGate({super.key, required this.isWrite, required this.child});

  final bool isWrite;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<NlcAppState>();
    final localizations = AppLocalizations.of(context)!;
    return FutureBuilder<DeviceIoCompatibility>(
      future: appState.checkDeviceIoCompatibility(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == DeviceIoCompatibility.supported) return child;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: NlcPageBody(
            maxWidth: 760,
            children: [
              NlcPageHeader(
                eyebrow: localizations.nlc_nav_device,
                eyebrowIcon: isWrite ? Icons.edit_rounded : Icons.nfc_rounded,
                title: isWrite
                    ? localizations.write_card
                    : localizations.read_card,
              ),
              const SizedBox(height: 24),
              if (status == null)
                NlcCard(
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text(localizations.device_io_checking)),
                    ],
                  ),
                )
              else
                DeviceIoNotice(status: status),
            ],
          ),
        );
      },
    );
  }
}

/// Explique pourquoi la lecture et l'écriture sont indisponibles avec l'appareil connecté.
class DeviceIoNotice extends StatelessWidget {
  const DeviceIoNotice({super.key, required this.status});

  final DeviceIoCompatibility status;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.read<NlcAppState>();
    final message = switch (status) {
      DeviceIoCompatibility.supported => '',
      DeviceIoCompatibility.ultraRequired =>
        localizations.device_io_ultra_required,
      DeviceIoCompatibility.legacyProtocol =>
        localizations.device_io_legacy_protocol,
      DeviceIoCompatibility.missingCommands =>
        localizations.device_io_missing_commands,
      DeviceIoCompatibility.checkFailed => localizations.device_io_check_failed,
    };
    return NlcCard(
      borderColor: Nlc.rose500.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Nlc.rose400,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Nlc.slate200, height: 1.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    context.read<NlcNavigation>().go(NlcDestination.device),
                icon: const Icon(Icons.memory_rounded, size: 18),
                label: Text(localizations.device_dashboard),
              ),
              if (status == DeviceIoCompatibility.checkFailed)
                TextButton(
                  onPressed: appState.retryDeviceIoCompatibility,
                  child: Text(localizations.device_io_retry),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
