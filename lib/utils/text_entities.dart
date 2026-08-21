import 'package:flutter/services.dart';
import 'package:tdlib/td_api.dart' as td;

/// Parsed inline markup from composer toolbar / markdown shortcuts.
class ParsedFormattedText {
  const ParsedFormattedText({required this.text, required this.entities});

  final String text;
  final List<td.TextEntity> entities;
}

ParsedFormattedText parseComposerText(String raw) {
  final buffer = StringBuffer();
  final entities = <td.TextEntity>[];
  var i = 0;
  while (i < raw.length) {
    if (raw.startsWith('**', i)) {
      final end = raw.indexOf('**', i + 2);
      if (end > i + 2) {
        final inner = raw.substring(i + 2, end);
        final offset = buffer.length;
        buffer.write(inner);
        entities.add(td.TextEntity(
          offset: offset,
          length: inner.length,
          type: const td.TextEntityTypeBold(),
        ));
        i = end + 2;
        continue;
      }
    }
    if (raw.startsWith('||', i)) {
      final end = raw.indexOf('||', i + 2);
      if (end > i + 2) {
        final inner = raw.substring(i + 2, end);
        final offset = buffer.length;
        buffer.write(inner);
        entities.add(td.TextEntity(
          offset: offset,
          length: inner.length,
          type: const td.TextEntityTypeSpoiler(),
        ));
        i = end + 2;
        continue;
      }
    }
    if (raw.startsWith('`', i)) {
      final end = raw.indexOf('`', i + 1);
      if (end > i + 1) {
        final inner = raw.substring(i + 1, end);
        final offset = buffer.length;
        buffer.write(inner);
        entities.add(td.TextEntity(
          offset: offset,
          length: inner.length,
          type: const td.TextEntityTypeCode(),
        ));
        i = end + 1;
        continue;
      }
    }
    if (raw[i] == '*' && (i + 1 < raw.length) && raw[i + 1] != '*') {
      final end = raw.indexOf('*', i + 1);
      if (end > i + 1) {
        final inner = raw.substring(i + 1, end);
        final offset = buffer.length;
        buffer.write(inner);
        entities.add(td.TextEntity(
          offset: offset,
          length: inner.length,
          type: const td.TextEntityTypeItalic(),
        ));
        i = end + 1;
        continue;
      }
    }
    buffer.write(raw[i]);
    i += 1;
  }
  return ParsedFormattedText(text: buffer.toString(), entities: entities);
}

td.FormattedText buildFormattedText(String raw) {
  final parsed = parseComposerText(raw);
  return td.FormattedText(text: parsed.text, entities: parsed.entities);
}

String wrapSelection(String text, TextSelection selection, String wrapper) {
  if (!selection.isValid) return text + wrapper + wrapper;
  final start = selection.start;
  final end = selection.end;
  if (start == end) {
    return '${text.substring(0, start)}$wrapper$wrapper${text.substring(start)}';
  }
  final selected = text.substring(start, end);
  return '${text.substring(0, start)}$wrapper$selected$wrapper${text.substring(end)}';
}

String wrapMention(String text, TextSelection selection, String username) {
  final mention = '@$username ';
  if (!selection.isValid) return '$text$mention';
  return '${text.substring(0, selection.start)}$mention${text.substring(selection.end)}';
}
