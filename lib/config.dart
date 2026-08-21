import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static int get apiId {
    final raw = dotenv.env['TELEGRAM_API_ID'] ?? '0';
    return int.tryParse(raw) ?? 0;
  }

  static String get apiHash => dotenv.env['TELEGRAM_API_HASH'] ?? '';

  static bool get hasCredentials =>
      apiId > 0 && apiHash.isNotEmpty && apiHash != 'replace_me';
}
