import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tdlib/focus_message_entities.dart';

/// Builds a [TextSpan] tree from plain text + TDLib-style entities.
class RichTextBuilder {
  RichTextBuilder({
    required this.text,
    required this.entities,
    required this.baseStyle,
    this.onMentionTap,
    this.primaryColor,
  });

  final String text;
  final List<FocusTextEntity> entities;
  final TextStyle baseStyle;
  final void Function(int userId)? onMentionTap;
  final Color? primaryColor;

  TextSpan build() {
    if (text.isEmpty) return TextSpan(text: '', style: baseStyle);
    if (entities.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final sorted = List<FocusTextEntity>.from(entities)
      ..sort((a, b) => a.offset.compareTo(b.offset));

    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final entity in sorted) {
      final start = entity.offset.clamp(0, text.length);
      final end = (entity.offset + entity.length).clamp(0, text.length);
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start), style: baseStyle));
      }
      if (start >= end) continue;

      final slice = text.substring(start, end);
      spans.add(_styledSpan(slice, entity));
      cursor = end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    return TextSpan(children: spans, style: baseStyle);
  }

  InlineSpan _styledSpan(String slice, FocusTextEntity entity) {
    final primary = primaryColor ?? baseStyle.color;
    switch (entity.type) {
      case FocusEntityType.bold:
        return TextSpan(
          text: slice,
          style: baseStyle.merge(const TextStyle(fontWeight: FontWeight.w700)),
        );
      case FocusEntityType.italic:
        return TextSpan(
          text: slice,
          style: baseStyle.merge(const TextStyle(fontStyle: FontStyle.italic)),
        );
      case FocusEntityType.code:
        return TextSpan(
          text: slice,
          style: baseStyle.merge(TextStyle(
            fontFamily: 'monospace',
            fontSize: (baseStyle.fontSize ?? 15) - 1,
            backgroundColor: Colors.black.withValues(alpha: 0.12),
          )),
        );
      case FocusEntityType.spoiler:
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _SpoilerText(text: slice, style: baseStyle),
        );
      case FocusEntityType.url:
      case FocusEntityType.textUrl:
        final url = entity.url ?? slice;
        return TextSpan(
          text: slice,
          style: baseStyle.merge(TextStyle(
            color: primary,
            decoration: TextDecoration.underline,
          )),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _openUrl(url),
        );
      case FocusEntityType.mention:
        return TextSpan(
          text: slice,
          style: baseStyle.merge(TextStyle(
            color: primary,
            fontWeight: FontWeight.w600,
          )),
        );
      case FocusEntityType.mentionName:
        final userId = entity.userId;
        return TextSpan(
          text: slice,
          style: baseStyle.merge(TextStyle(
            color: primary,
            fontWeight: FontWeight.w600,
          )),
          recognizer: userId != null
              ? (TapGestureRecognizer()..onTap = () => onMentionTap?.call(userId))
              : null,
        );
      default:
        return TextSpan(text: slice, style: baseStyle);
    }
  }

  static Future<void> _openUrl(String url) async {
    var href = url.trim();
    if (href.isEmpty) return;
    if (!href.startsWith('http://') && !href.startsWith('https://')) {
      href = 'https://$href';
    }
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _SpoilerText extends StatefulWidget {
  const _SpoilerText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_SpoilerText> createState() => _SpoilerTextState();
}

class _SpoilerTextState extends State<_SpoilerText> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    if (_revealed) {
      return Text(widget.text, style: widget.style);
    }
    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          widget.text.replaceAll(RegExp(r'.'), '·'),
          style: widget.style.copyWith(color: Colors.transparent),
        ),
      ),
    );
  }
}
