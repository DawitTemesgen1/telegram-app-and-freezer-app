import 'package:flutter/material.dart';

import '../../tdlib/telegram_client.dart';

/// Banner shown when TDLib connection is offline or reconnecting.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.state});

  final TdConnectionState state;

  @override
  Widget build(BuildContext context) {
    if (state == TdConnectionState.ready) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final (label, icon, color) = switch (state) {
      TdConnectionState.connecting => (
          'Connecting…',
          Icons.sync,
          theme.colorScheme.primary,
        ),
      TdConnectionState.waitingForNetwork => (
          'Waiting for network…',
          Icons.wifi_off,
          theme.colorScheme.error,
        ),
      TdConnectionState.updating => (
          'Syncing…',
          Icons.cloud_sync_outlined,
          theme.colorScheme.primary,
        ),
      _ => (
          'Offline — messages may be delayed',
          Icons.cloud_off_outlined,
          theme.colorScheme.error,
        ),
    };

    return Material(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
