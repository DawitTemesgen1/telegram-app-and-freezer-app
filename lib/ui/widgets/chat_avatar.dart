import 'dart:io';

import 'package:flutter/material.dart';

import '../../tdlib/focus_chat.dart';

/// Circular group/channel avatar with photo or letter fallback.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.chat,
    this.imagePath,
    this.size = 48,
    this.highlighted = false,
    this.showKindBadge = true,
  });

  final FocusChat chat;
  final String? imagePath;
  final double size;
  final bool highlighted;
  final bool showKindBadge;

  bool get _isChannel => chat.kind == 'channel';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final initial = chat.title.trim().isEmpty
        ? '?'
        : chat.title.trim().substring(0, 1).toUpperCase();
    final hasPhoto = imagePath != null &&
        imagePath!.isNotEmpty &&
        File(imagePath!).existsSync();

    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: highlighted
                    ? [
                        accent.withValues(alpha: 0.45),
                        accent.withValues(alpha: 0.18),
                      ]
                    : [
                        theme.colorScheme.surfaceContainerHighest,
                        theme.colorScheme.surface.withValues(alpha: 0.9),
                      ],
              ),
        border: Border.all(
          color: accent.withValues(alpha: highlighted ? 0.55 : 0.22),
          width: 1.2,
        ),
        image: hasPhoto
            ? DecorationImage(
                image: FileImage(File(imagePath!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasPhoto
          ? null
          : Text(
              initial,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
                fontSize: size * 0.38,
              ),
            ),
    );

    if (!showKindBadge) return circle;

    final badgeSize = (size * 0.38).clamp(14.0, 20.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(
              _isChannel ? Icons.campaign_outlined : Icons.groups_outlined,
              size: badgeSize * 0.6,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }
}
