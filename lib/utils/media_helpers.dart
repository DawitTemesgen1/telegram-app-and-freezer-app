import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> saveMediaToDownloads(String sourcePath, {String? fileName}) async {
  try {
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final name = fileName ?? p.basename(sourcePath);
    Directory? targetDir;
    if (Platform.isLinux || Platform.isAndroid) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final downloads = Directory(p.join(home, 'Downloads'));
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        targetDir = downloads;
      }
    }
    targetDir ??= await getApplicationDocumentsDirectory();
    final dest = File(p.join(targetDir.path, name));
    await source.copy(dest.path);
    return dest.path;
  } catch (_) {
    return null;
  }
}

Future<void> copyToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

bool isPdfFileName(String? name) {
  if (name == null) return false;
  return name.toLowerCase().endsWith('.pdf');
}

bool isGifFileName(String? name) {
  if (name == null) return false;
  final lower = name.toLowerCase();
  return lower.endsWith('.gif') || lower.endsWith('.mp4');
}
