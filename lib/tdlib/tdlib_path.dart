import 'dart:io';

/// Resolves the native TDLib JSON library path for the current platform.
String? resolveTdlibPath() {
  if (Platform.isAndroid) {
    return 'libtdjson.so';
  }

  if (Platform.isLinux) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      // Bundled next to the Flutter Linux executable.
      '$exeDir/lib/libtdjson.so',
      // Same directory as the executable (some launch layouts).
      '$exeDir/libtdjson.so',
      // Dev checkout: linux/libs/libtdjson.so relative to CWD.
      '${Directory.current.path}/linux/libs/libtdjson.so',
      // Override via env.
      if (Platform.environment['TG_FOCUS_TDLIB'] != null)
        Platform.environment['TG_FOCUS_TDLIB']!,
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    // Last resort: let the dynamic linker search.
    return 'libtdjson.so';
  }

  return null;
}
