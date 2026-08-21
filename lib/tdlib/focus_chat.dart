import 'dart:convert';

/// Lightweight chat info parsed from raw TDLib JSON (version-tolerant).
class FocusChat {
  const FocusChat({
    required this.id,
    required this.title,
    required this.kind,
    this.lastPreview = '',
    this.unreadCount = 0,
    this.lastMessageDate = 0,
    this.lastReadInboxMessageId = 0,
    this.isMarkedAsUnread = false,
    this.memberCount = 0,
    this.photoFileId,
  });

  final int id;
  final String title;

  /// One of: private, group, channel, secret, unknown
  final String kind;
  final String lastPreview;
  final int unreadCount;
  final int lastMessageDate;
  final int lastReadInboxMessageId;
  final bool isMarkedAsUnread;
  final int memberCount;

  /// TDLib file id for the small chat photo, if any.
  final int? photoFileId;

  bool get isGroupOrChannel => kind == 'group' || kind == 'channel';

  FocusChat copyWith({
    String? title,
    String? lastPreview,
    int? unreadCount,
    int? lastMessageDate,
    int? lastReadInboxMessageId,
    bool? isMarkedAsUnread,
    int? memberCount,
    int? photoFileId,
    bool clearPhotoFileId = false,
  }) {
    return FocusChat(
      id: id,
      title: title ?? this.title,
      kind: kind,
      lastPreview: lastPreview ?? this.lastPreview,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageDate: lastMessageDate ?? this.lastMessageDate,
      lastReadInboxMessageId:
          lastReadInboxMessageId ?? this.lastReadInboxMessageId,
      isMarkedAsUnread: isMarkedAsUnread ?? this.isMarkedAsUnread,
      memberCount: memberCount ?? this.memberCount,
      photoFileId:
          clearPhotoFileId ? null : (photoFileId ?? this.photoFileId),
    );
  }

  static FocusChat? tryParse(Map<String, dynamic> json) {
    try {
      final id = asInt(json['id']);
      if (id == 0) return null;
      final title = (json['title'] as String?)?.trim() ?? '';
      final type = json['type'];
      var kind = 'unknown';
      if (type is Map<String, dynamic>) {
        switch (type['@type']) {
          case 'chatTypePrivate':
            kind = 'private';
            break;
          case 'chatTypeBasicGroup':
            kind = 'group';
            break;
          case 'chatTypeSupergroup':
            kind = type['is_channel'] == true ? 'channel' : 'group';
            break;
          case 'chatTypeSecret':
            kind = 'secret';
            break;
        }
      }

      var preview = '';
      var date = 0;
      final last = json['last_message'];
      if (last is Map<String, dynamic>) {
        date = asInt(last['date']);
        preview = previewFromContent(last['content']);
      }

      var members = 0;
      if (type is Map<String, dynamic>) {
        if (type['@type'] == 'chatTypeBasicGroup') {
          members = asInt(type['basic_group_id']);
        } else if (type['@type'] == 'chatTypeSupergroup') {
          members = asInt(type['supergroup_id']);
        }
      }

      return FocusChat(
        id: id,
        title: title.isEmpty ? 'Chat $id' : title,
        kind: kind,
        lastPreview: preview,
        unreadCount: asInt(json['unread_count']),
        lastMessageDate: date,
        lastReadInboxMessageId: asInt(json['last_read_inbox_message_id']),
        isMarkedAsUnread: json['is_marked_as_unread'] == true,
        memberCount: members,
        photoFileId: photoFileIdFromJson(json['photo']),
      );
    } catch (_) {
      return null;
    }
  }

  static int? photoFileIdFromJson(dynamic photo) {
    if (photo is! Map) return null;
    final small = photo['small'];
    if (small is! Map) return null;
    final id = asInt(small['id']);
    return id == 0 ? null : id;
  }

  static int asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static String previewFromContent(dynamic content) {
    if (content is! Map<String, dynamic>) return '';
    switch (content['@type']) {
      case 'messageText':
        final text = content['text'];
        if (text is Map && text['text'] is String) return text['text'] as String;
        return '';
      case 'messagePhoto':
        return captionOr(content, '[photo]');
      case 'messageVideo':
        return captionOr(content, '[video]');
      case 'messageAudio':
        final title = content['title'];
        if (title is String && title.trim().isNotEmpty) return '♫ $title';
        return captionOr(content, '[audio]');
      case 'messageDocument':
        final doc = content['document'];
        if (doc is Map && doc['file_name'] is String) {
          return doc['file_name'] as String;
        }
        return captionOr(content, '[file]');
      case 'messageSticker':
        return '[sticker]';
      case 'messageVoiceNote':
        return '[voice]';
      case 'messageAnimation':
        return captionOr(content, '[gif]');
      default:
        return '[message]';
    }
  }

  static String captionOr(Map<String, dynamic> content, String fallback) {
    final caption = content['caption'];
    if (caption is Map && caption['text'] is String) {
      final text = (caption['text'] as String).trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static Map<String, dynamic>? decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }
}
