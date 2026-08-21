import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-chat notification prefs and local message pins.
class ChatPrefsStore extends ChangeNotifier {
  static const _mentionsOnlyKey = 'notify_mentions_only';
  static const _defaultHidePreviewKey = 'notify_hide_preview_default';
  static const _hidePreviewKey = 'chat_hide_preview';
  static const _soundKey = 'chat_sound';
  static const _localPinsKey = 'local_pinned_messages';
  static const _markedUnreadKey = 'marked_unread_chats';

  bool _mentionsOnly = false;
  bool _defaultHidePreview = false;
  final Map<int, bool> _hidePreviewByChat = {};
  final Map<int, String> _soundByChat = {};
  final Map<int, List<int>> _localPinnedIds = {};
  final Set<int> _locallyMarkedUnread = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get mentionsOnly => _mentionsOnly;
  bool get defaultHidePreview => _defaultHidePreview;

  bool hidePreviewFor(int chatId) =>
      _hidePreviewByChat[chatId] ?? _defaultHidePreview;

  /// `default` or `silent`.
  String soundFor(int chatId) => _soundByChat[chatId] ?? 'default';

  List<int> localPinnedIds(int chatId) =>
      List.unmodifiable(_localPinnedIds[chatId] ?? const []);

  bool isLocallyPinned(int chatId, int messageId) =>
      _localPinnedIds[chatId]?.contains(messageId) == true;

  bool isLocallyMarkedUnread(int chatId) => _locallyMarkedUnread.contains(chatId);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mentionsOnly = prefs.getBool(_mentionsOnlyKey) ?? false;
    _defaultHidePreview = prefs.getBool(_defaultHidePreviewKey) ?? false;

    _hidePreviewByChat.clear();
    for (final entry in prefs.getStringList(_hidePreviewKey) ?? const []) {
      final sep = entry.indexOf(':');
      if (sep <= 0) continue;
      final id = int.tryParse(entry.substring(0, sep));
      if (id == null) continue;
      _hidePreviewByChat[id] = entry.substring(sep + 1) == '1';
    }

    _soundByChat.clear();
    for (final entry in prefs.getStringList(_soundKey) ?? const []) {
      final sep = entry.indexOf(':');
      if (sep <= 0) continue;
      final id = int.tryParse(entry.substring(0, sep));
      if (id == null) continue;
      _soundByChat[id] = entry.substring(sep + 1);
    }

    _localPinnedIds.clear();
    final pinsRaw = prefs.getString(_localPinsKey);
    if (pinsRaw != null && pinsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(pinsRaw);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final chatId = int.tryParse(entry.key);
            if (chatId == null) continue;
            final ids = (entry.value as List? ?? const [])
                .map((e) => int.tryParse('$e'))
                .whereType<int>()
                .toList();
            if (ids.isNotEmpty) _localPinnedIds[chatId] = ids;
          }
        }
      } catch (_) {}
    }

    _locallyMarkedUnread.clear();
    for (final id in prefs.getStringList(_markedUnreadKey) ?? const []) {
      final chatId = int.tryParse(id);
      if (chatId != null) _locallyMarkedUnread.add(chatId);
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> setMentionsOnly(bool value) async {
    if (_mentionsOnly == value) return;
    _mentionsOnly = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mentionsOnlyKey, value);
  }

  Future<void> setDefaultHidePreview(bool value) async {
    if (_defaultHidePreview == value) return;
    _defaultHidePreview = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultHidePreviewKey, value);
  }

  Future<void> setHidePreview(int chatId, bool hide) async {
    _hidePreviewByChat[chatId] = hide;
    notifyListeners();
    await _persistHidePreview();
  }

  Future<void> setSound(int chatId, String sound) async {
    if (sound == 'default') {
      _soundByChat.remove(chatId);
    } else {
      _soundByChat[chatId] = sound;
    }
    notifyListeners();
    await _persistSound();
  }

  Future<void> toggleLocalPin(int chatId, int messageId) async {
    final list = _localPinnedIds.putIfAbsent(chatId, () => []);
    if (list.contains(messageId)) {
      list.remove(messageId);
      if (list.isEmpty) _localPinnedIds.remove(chatId);
    } else {
      list.insert(0, messageId);
    }
    notifyListeners();
    await _persistLocalPins();
  }

  Future<void> setLocallyMarkedUnread(int chatId, bool marked) async {
    if (marked) {
      _locallyMarkedUnread.add(chatId);
    } else {
      _locallyMarkedUnread.remove(chatId);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _markedUnreadKey,
      _locallyMarkedUnread.map((id) => '$id').toList(),
    );
  }

  Future<void> toggleLocallyMarkedUnread(int chatId) =>
      setLocallyMarkedUnread(chatId, !isLocallyMarkedUnread(chatId));

  Future<void> _persistHidePreview() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _hidePreviewKey,
      _hidePreviewByChat.entries
          .map((e) => '${e.key}:${e.value ? 1 : 0}')
          .toList(),
    );
  }

  Future<void> _persistSound() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _soundKey,
      _soundByChat.entries.map((e) => '${e.key}:${e.value}').toList(),
    );
  }

  Future<void> _persistLocalPins() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _localPinnedIds.map((k, v) => MapEntry('$k', v)),
    );
    await prefs.setString(_localPinsKey, encoded);
  }
}
