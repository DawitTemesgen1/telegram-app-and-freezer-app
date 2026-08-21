import 'package:tdlib/td_api.dart' as td;

bool isGroupOrChannel(td.Chat chat) {
  final type = chat.type;
  return type is td.ChatTypeBasicGroup || type is td.ChatTypeSupergroup;
}

String messagePreview(td.Message? message) {
  if (message == null) return '';
  final content = message.content;
  if (content is td.MessageText) return content.text.text;
  if (content is td.MessagePhoto) {
    final caption = content.caption.text;
    return caption.isEmpty ? '[photo]' : caption;
  }
  if (content is td.MessageVideo) {
    final caption = content.caption.text;
    return caption.isEmpty ? '[video]' : caption;
  }
  if (content is td.MessageAnimation) {
    final caption = content.caption.text;
    return caption.isEmpty ? '[gif]' : caption;
  }
  if (content is td.MessageDocument) {
    final caption = content.caption.text;
    return caption.isEmpty ? '[file]' : caption;
  }
  if (content is td.MessageSticker) return '[sticker]';
  if (content is td.MessageVoiceNote) return '[voice]';
  if (content is td.MessageVideoNote) return '[video note]';
  if (content is td.MessageAudio) return '[audio]';
  if (content is td.MessageLocation) return '[location]';
  if (content is td.MessageContact) return '[contact]';
  if (content is td.MessagePoll) return '[poll] ${content.poll.question}';
  return '[message]';
}

String formatMessageTime(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final now = DateTime.now();
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${dt.day}/${dt.month} $hh:$mm';
}

String formatDateSeparator(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  if (dt.year == now.year) {
    return '${dt.day} ${months[dt.month - 1]}';
  }
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

bool isSameDay(int aUnix, int bUnix) {
  final a = DateTime.fromMillisecondsSinceEpoch(aUnix * 1000);
  final b = DateTime.fromMillisecondsSinceEpoch(bUnix * 1000);
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
