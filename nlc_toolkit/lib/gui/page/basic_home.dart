import 'package:nlc_toolkit/connector/serial_abstract.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/helpers/general.dart';
import 'package:nlc_toolkit/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BasicHomePage extends StatelessWidget {
  const BasicHomePage({
    super.key,
    required this.onRead,
    required this.onWrite,
    required this.onAdvanced,
    required this.onDeviceDashboard,
  });

  final VoidCallback onRead;
  final VoidCallback onWrite;
  final VoidCallback onAdvanced;
  final VoidCallback onDeviceDashboard;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final connector = appState.connector!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 24,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.nfc_rounded, color: scheme.onPrimary, size: 19),
            ),
            const SizedBox(width: 11),
            const Text('NLC Toolkit'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: localizations.disconnect_device,
            icon: const Icon(Icons.link_off_rounded),
            onPressed: () => appState.disconnect(manual: true),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 20 : 40,
                    vertical: compact ? 28 : 44,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.nlc_workspace_eyebrow,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.7,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        localizations.nlc_workspace_title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: compact ? 30 : 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        localizations.nlc_workspace_subtitle,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 30),
                      _ConnectedDeviceCard(
                        deviceName:
                            'Chameleon ${chameleonDeviceName(connector.device)}',
                        portName: connector.portName,
                        isBluetooth:
                            connector.connectionType == ConnectionType.ble,
                        statusLabel: localizations.nlc_device_connected,
                      ),
                      const SizedBox(height: 36),
                      FutureBuilder<DeviceIoCompatibility>(
                        future: appState.checkDeviceIoCompatibility(),
                        builder: (context, snapshot) {
                          final status = snapshot.data;
                          final available =
                              status == DeviceIoCompatibility.supported;
                          final readCard = _HomeActionCard(
                            number: '01',
                            icon: Icons.nfc_rounded,
                            title: localizations.read_card,
                            description:
                                localizations.nlc_read_action_description,
                            enabled: available,
                            onTap: onRead,
                          );
                          final writeCard = _HomeActionCard(
                            number: '02',
                            icon: Icons.edit_note_rounded,
                            title: localizations.write_card,
                            description:
                                localizations.nlc_write_action_description,
                            enabled: available,
                            onTap: onWrite,
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (status == null) ...[
                                _StatusPanel(
                                  message: localizations.device_io_checking,
                                  loading: true,
                                ),
                                const SizedBox(height: 22),
                              ] else if (!available) ...[
                                DeviceIoNotice(
                                  status: status,
                                  onDeviceDashboard: onDeviceDashboard,
                                ),
                                const SizedBox(height: 22),
                              ],
                              Text(
                                localizations.nlc_actions_title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (compact) ...[
                                readCard,
                                const SizedBox(height: 14),
                                writeCard,
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: readCard),
                                    const SizedBox(width: 16),
                                    Expanded(child: writeCard),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      _AdvancedLink(
                        title: localizations.advanced,
                        description: localizations.advanced_description,
                        onTap: onAdvanced,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  const _ConnectedDeviceCard({
    required this.deviceName,
    required this.portName,
    required this.isBluetooth,
    required this.statusLabel,
  });

  final String deviceName;
  final String portName;
  final bool isBluetooth;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              isBluetooth ? Icons.bluetooth_rounded : Icons.usb_rounded,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: scheme.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  deviceName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  portName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.check_circle_rounded, color: scheme.tertiary, size: 22),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onTap,
  });

  final String number;
  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(icon, color: scheme.primary, size: 28),
                    ),
                    const Spacer(),
                    Text(
                      number,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: scheme.onPrimary,
                      size: 20,
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

class _AdvancedLink extends StatelessWidget {
  const _AdvancedLink({
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, color: scheme.secondary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: scheme.onSurfaceVariant,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.message, this.loading = false});

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          if (loading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          else
            Icon(Icons.info_outline_rounded, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

/// Prevents the read and write flows from opening on unsupported firmware.
class DeviceIoGate extends StatelessWidget {
  const DeviceIoGate({
    super.key,
    required this.isWrite,
    required this.onDeviceDashboard,
    required this.child,
  });

  final bool isWrite;
  final VoidCallback onDeviceDashboard;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    return FutureBuilder<DeviceIoCompatibility>(
      future: appState.checkDeviceIoCompatibility(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == DeviceIoCompatibility.supported) {
          return child;
        }
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            title: Text(
              isWrite ? localizations.write_card : localizations.read_card,
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: status == null
                    ? _StatusPanel(
                        message: localizations.device_io_checking,
                        loading: true,
                      )
                    : DeviceIoNotice(
                        status: status,
                        onDeviceDashboard: onDeviceDashboard,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class DeviceIoNotice extends StatelessWidget {
  const DeviceIoNotice({
    super.key,
    required this.status,
    required this.onDeviceDashboard,
  });

  final DeviceIoCompatibility status;
  final VoidCallback onDeviceDashboard;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.read<ChameleonGUIState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.error.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: scheme.error, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                if (status != DeviceIoCompatibility.ultraRequired ||
                    status == DeviceIoCompatibility.checkFailed) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (status != DeviceIoCompatibility.ultraRequired)
                        OutlinedButton(
                          onPressed: onDeviceDashboard,
                          child: Text(localizations.device_dashboard),
                        ),
                      if (status == DeviceIoCompatibility.checkFailed)
                        TextButton(
                          onPressed: appState.retryDeviceIoCompatibility,
                          child: Text(localizations.device_io_retry),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
