import 'package:flutter/material.dart';

import '../../tdlib/telegram_client.dart';

class PinnedMessagesBar extends StatelessWidget {
  const PinnedMessagesBar({
    super.key,
    required this.pinnedMessages,
    required this.onTap,
    required this.onClose,
  });

  final List<FocusMessage> pinnedMessages;
  final void Function(FocusMessage message) onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (pinnedMessages.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final current = pinnedMessages.first;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => onTap(current),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pinnedMessages.length > 1
                          ? '${pinnedMessages.length} pinned messages'
                          : 'Pinned message',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      current.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (pinnedMessages.length > 1)
                IconButton(
                  tooltip: 'Next pin',
                  icon: const Icon(Icons.expand_more),
                  onPressed: () {
                    final next = pinnedMessages.length > 1
                        ? pinnedMessages[1]
                        : pinnedMessages.first;
                    onTap(next);
                  },
                ),
              IconButton(
                tooltip: 'Hide',
                icon: const Icon(Icons.close, size: 20),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
