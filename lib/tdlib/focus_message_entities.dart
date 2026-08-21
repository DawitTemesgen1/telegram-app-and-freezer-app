/// Parsed text entity from TDLib message content.
enum FocusEntityType {
  bold,
  italic,
  code,
  spoiler,
  url,
  textUrl,
  mention,
  mentionName,
  unknown,
}

class FocusTextEntity {
  const FocusTextEntity({
    required this.offset,
    required this.length,
    required this.type,
    this.url,
    this.userId,
  });

  final int offset;
  final int length;
  final FocusEntityType type;
  final String? url;
  final int? userId;

  static List<FocusTextEntity> fromTdJson(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final out = <FocusTextEntity>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final offset = _asInt(item['offset']);
      final length = _asInt(item['length']);
      if (length <= 0) continue;
      final typeMap = item['type'];
      if (typeMap is! Map<String, dynamic>) continue;
      final typeName = typeMap['@type'] as String? ?? '';
      final parsed = switch (typeName) {
        'textEntityTypeBold' => FocusEntityType.bold,
        'textEntityTypeItalic' => FocusEntityType.italic,
        'textEntityTypeCode' => FocusEntityType.code,
        'textEntityTypeSpoiler' => FocusEntityType.spoiler,
        'textEntityTypeUrl' => FocusEntityType.url,
        'textEntityTypeTextUrl' => FocusEntityType.textUrl,
        'textEntityTypeMention' => FocusEntityType.mention,
        'textEntityTypeMentionName' => FocusEntityType.mentionName,
        _ => FocusEntityType.unknown,
      };
      if (parsed == FocusEntityType.unknown) continue;
      out.add(FocusTextEntity(
        offset: offset,
        length: length,
        type: parsed,
        url: typeName == 'textEntityTypeTextUrl'
            ? typeMap['url'] as String?
            : null,
        userId: typeName == 'textEntityTypeMentionName'
            ? _asInt(typeMap['user_id'])
            : null,
      ));
    }
    return out;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
