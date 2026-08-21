import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../tdlib/focus_chat.dart';
import '../tdlib/telegram_client.dart';

Future<String?> exportChatTranscript({
  required FocusChat chat,
  required List<FocusMessage> messages,
  required String Function(FocusMessage) senderName,
}) async {
  final buffer = StringBuffer();
  buffer.writeln('TG Focus export — ${chat.title}');
  buffer.writeln('Exported ${DateTime.now().toIso8601String()}');
  buffer.writeln('=' * 40);
  buffer.writeln();

  for (final msg in messages) {
    final dt = DateTime.fromMillisecondsSinceEpoch(msg.date * 1000);
    final who = msg.isOutgoing ? 'You' : senderName(msg);
    buffer.writeln('[${dt.toIso8601String()}] $who: ${msg.text}');
  }

  final dir = await getApplicationDocumentsDirectory();
  final exportsDir = Directory(p.join(dir.path, 'exports'));
  if (!await exportsDir.exists()) await exportsDir.create(recursive: true);
  final safeTitle = chat.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
  final fileName =
      '${safeTitle.isEmpty ? 'chat' : safeTitle}_${DateTime.now().millisecondsSinceEpoch}.txt';
  final file = File(p.join(exportsDir.path, fileName));
  final bytes = utf8.encode(buffer.toString());
  await file.writeAsBytes(bytes);

  final saved = await FilePicker.saveFile(
    dialogTitle: 'Save chat transcript',
    fileName: fileName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: const ['txt'],
  );
  if (saved != null) {
    return saved.toString();
  }
  return file.path;
}
