import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unsent composer text keyed by chat id.
class DraftsStore extends ChangeNotifier {
  static const _key = 'chat_drafts';

  final Map<int, String> _drafts = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    _drafts.clear();
    for (final entry in raw) {
      final sep = entry.indexOf(':');
      if (sep <= 0) continue;
      final id = int.tryParse(entry.substring(0, sep));
      if (id == null) continue;
      _drafts[id] = entry.substring(sep + 1);
    }
    _loaded = true;
    notifyListeners();
  }

  String draftFor(int chatId) => _drafts[chatId] ?? '';

  Future<void> setDraft(int chatId, String text) async {
    final trimmed = text; // keep whitespace while composing
    if (trimmed.isEmpty) {
      if (!_drafts.containsKey(chatId)) return;
      _drafts.remove(chatId);
    } else {
      if (_drafts[chatId] == trimmed) return;
      _drafts[chatId] = trimmed;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clearDraft(int chatId) async {
    if (!_drafts.containsKey(chatId)) return;
    _drafts.remove(chatId);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _drafts.entries.map((e) => '${e.key}:${e.value}').toList(),
    );
  }
}
