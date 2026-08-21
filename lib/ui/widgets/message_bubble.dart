import 'package:flutter/material.dart';

import '../../tdlib/telegram_client.dart';
import '../../theme/app_theme.dart';
import '../../utils/message_utils.dart';
import '../../utils/rich_text_builder.dart';
import 'inline_video_player.dart';
import 'voice_waveform.dart';

/// Single chat message bubble.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.senderName,
    required this.showSenderName,
    required this.onLongPress,
    this.onTap,
    this.onReplyTap,
    this.onRetry,
    this.onMentionTap,
    this.selected = false,
    this.selectionMode = false,
    this.onSelectToggle,
    this.locallyPinned = false,
    this.downloadProgress,
    this.inlineVideoPath,
    this.inlineAnimationPath,
  });

  final FocusMessage message;
  final String senderName;
  final bool showSenderName;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;
  final VoidCallback? onReplyTap;
  final VoidCallback? onRetry;
  final void Function(int userId)? onMentionTap;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onSelectToggle;
  final bool locallyPinned;
  final double? downloadProgress;
  final String? inlineVideoPath;
  final String? inlineAnimationPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.isOutgoing;
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.35)
        : message.isFailed
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.45)
            : isDark
                ? (mine ? AppTheme.bubbleOutgoing : AppTheme.bubbleIncoming)
                : (mine
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest);
    final hasHeader = (showSenderName && !mine) ||
        message.replyPreview != null ||
        locallyPinned ||
        message.isFailed;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectionMode)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 4),
              child: Checkbox(
                value: selected,
                onChanged: (_) => onSelectToggle?.call(),
              ),
            ),
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              onTap: message.isFailed
                  ? onRetry
                  : (selectionMode ? onSelectToggle : onTap),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                ),
                child: Container(
                  margin: EdgeInsets.only(
                    top: 2,
                    bottom: 2,
                    left: mine ? 36 : 0,
                    right: mine ? 0 : 36,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(mine ? 18 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 18),
                    ),
                    border: Border.all(
                      color: message.isFailed
                          ? theme.colorScheme.error
                          : selected
                              ? theme.colorScheme.primary
                              : mine
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.22)
                                  : theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.28),
                      width: selected || message.isFailed ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.22 : 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment:
                        mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      if (message.isFailed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 14,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Failed to send · tap to retry',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (locallyPinned)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.push_pin,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Pinned locally',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (showSenderName && !mine)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            12,
                            locallyPinned || message.isFailed ? 4 : 10,
                            12,
                            0,
                          ),
                          child: Text(
                            senderName,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      if (message.replyPreview != null)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            10,
                            (showSenderName && !mine) ||
                                    locallyPinned ||
                                    message.isFailed
                                ? 6
                                : 10,
                            10,
                            0,
                          ),
                          child: GestureDetector(
                            onTap: onReplyTap,
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.fromLTRB(10, 7, 10, 7),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface
                                    .withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border(
                                  left: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Text(
                                message.replyPreview!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      _buildContent(context, theme, hasHeader),
                      if (message.hasReactions)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: message.reactions.entries
                                .map(
                                  (e) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface
                                          .withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Text(
                                      '${e.key} ${e.value}',
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatMessageTime(message.date),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10.5,
                              ),
                            ),
                            if (downloadProgress != null &&
                                downloadProgress! < 1.0) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: downloadProgress,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    bool hasHeader,
  ) {
    if (inlineVideoPath != null && message.isVideo) {
      return Padding(
        padding: EdgeInsets.fromLTRB(8, hasHeader ? 6 : 8, 8, 0),
        child: InlineVideoPlayer(path: inlineVideoPath!),
      );
    }
    if (inlineAnimationPath != null && message.isAnimation) {
      return Padding(
        padding: EdgeInsets.fromLTRB(8, hasHeader ? 6 : 8, 8, 0),
        child: InlineVideoPlayer(
          path: inlineAnimationPath!,
          autoPlay: true,
          loop: true,
        ),
      );
    }
    if (message.isPhoto) {
      return _MediaTile(
        icon: Icons.image_outlined,
        title: 'Photo',
        subtitle: downloadProgress != null && downloadProgress! < 1.0
            ? 'Downloading…'
            : 'Tap to open',
        caption: message.text == '[photo]' ? null : message.text,
        paddedTop: hasHeader,
        progress: downloadProgress,
      );
    }
    if (message.isSticker) {
      return Padding(
        padding: EdgeInsets.fromLTRB(12, hasHeader ? 6 : 10, 12, 0),
        child: Text(
          message.fileName ?? message.text,
          style: const TextStyle(fontSize: 48),
        ),
      );
    }
    if (message.isAnimation) {
      return _MediaTile(
        icon: Icons.gif_box_outlined,
        title: message.fileName ?? 'GIF',
        subtitle: 'Tap to play inline',
        caption: message.text == '[gif]' ? null : message.text,
        paddedTop: hasHeader,
        progress: downloadProgress,
      );
    }
    if (message.isVideo) {
      return _MediaTile(
        icon: Icons.play_circle_outline,
        title: message.fileName ?? 'Video',
        subtitle: message.durationSeconds != null && message.durationSeconds! > 0
            ? _formatDuration(message.durationSeconds!)
            : 'Tap to play',
        caption: message.text.startsWith('[') ? null : message.text,
        paddedTop: hasHeader,
        progress: downloadProgress,
      );
    }
    if (message.isVoice) {
      return Padding(
        padding: EdgeInsets.fromLTRB(10, hasHeader ? 6 : 10, 10, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VoiceWaveform(active: false, progress: 0),
            const SizedBox(height: 4),
            Text(
              message.durationSeconds != null && message.durationSeconds! > 0
                  ? _formatDuration(message.durationSeconds!)
                  : 'Voice message',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (message.isAudio) {
      return _MediaTile(
        icon: Icons.audiotrack_rounded,
        title: message.fileName ?? 'Audio',
        subtitle: message.durationSeconds != null && message.durationSeconds! > 0
            ? _formatDuration(message.durationSeconds!)
            : 'Tap to play',
        caption: null,
        paddedTop: hasHeader,
        progress: downloadProgress,
      );
    }
    if (message.isFile) {
      return _MediaTile(
        icon: Icons.insert_drive_file_outlined,
        title: message.fileName ?? 'File',
        subtitle: 'Tap to open',
        caption: message.text == message.fileName
            ? null
            : (message.text.startsWith('[') ? null : message.text),
        paddedTop: hasHeader,
        progress: downloadProgress,
      );
    }

    final baseStyle = theme.textTheme.bodyMedium!.copyWith(
      height: 1.35,
      fontSize: 15,
    );
    final span = RichTextBuilder(
      text: message.text,
      entities: message.entities,
      baseStyle: baseStyle,
      primaryColor: theme.colorScheme.primary,
      onMentionTap: onMentionTap,
    ).build();

    return Padding(
      padding: EdgeInsets.fromLTRB(12, hasHeader ? 6 : 10, 12, 0),
      child: RichText(text: span),
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.paddedTop,
    this.caption,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool paddedTop;
  final String? caption;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, paddedTop ? 6 : 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.18),
                  theme.colorScheme.surface.withValues(alpha: 0.35),
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: theme.colorScheme.primary),
                    ),
                    if (progress != null && progress! < 1.0)
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                caption!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
