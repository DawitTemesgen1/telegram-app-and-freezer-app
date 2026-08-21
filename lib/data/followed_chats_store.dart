import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FollowedChatsStore extends ChangeNotifier {
  static const _key = 'followed_chat_ids';
  static const _mutedKey = 'muted_chat_ids';
  static const _pinnedKey = 'pinned_chat_ids';
  static const _onboardingKey = 'picker_completed';

  final Set<int> _ids = {};
  final Set<int> _mutedIds = {};
  final List<int> _pinnedIds = []; // order = pin order (first = top)
  bool _loaded = false;
  bool _pickerCompleted = false;

  Set<int> get ids => Set.unmodifiable(_ids);
  Set<int> get mutedIds => Set.unmodifiable(_mutedIds);
  List<int> get pinnedIds => List.unmodifiable(_pinnedIds);
  bool get isLoaded => _loaded;
  bool get isEmpty => _ids.isEmpty;
  bool get pickerCompleted => _pickerCompleted;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final muted = prefs.getStringList(_mutedKey) ?? const [];
    final pinned = prefs.getStringList(_pinnedKey) ?? const [];
    _ids
      ..clear()
      ..addAll(raw.map(int.parse));
    _mutedIds
      ..clear()
      ..addAll(muted.map(int.parse));
    _pinnedIds
      ..clear()
      ..addAll(
        pinned.map(int.parse).where(_ids.contains),
      );
    _pickerCompleted = prefs.getBool(_onboardingKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  bool isFollowed(int chatId) => _ids.contains(chatId);
  bool isMuted(int chatId) => _mutedIds.contains(chatId);
  bool isPinned(int chatId) => _pinnedIds.contains(chatId);

  Future<void> setFollowed(int chatId, bool followed) async {
    if (followed) {
      _ids.add(chatId);
    } else {
      _ids.remove(chatId);
      _mutedIds.remove(chatId);
      _pinnedIds.remove(chatId);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setMuted(int chatId, bool muted) async {
    if (muted) {
      _mutedIds.add(chatId);
    } else {
      _mutedIds.remove(chatId);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> toggleMuted(int chatId) => setMuted(chatId, !isMuted(chatId));

  Future<void> setPinned(int chatId, bool pinned) async {
    if (!_ids.contains(chatId)) return;
    _pinnedIds.remove(chatId);
    if (pinned) {
      _pinnedIds.insert(0, chatId);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> togglePinned(int chatId) =>
      setPinned(chatId, !isPinned(chatId));

  Future<void> replaceAll(Set<int> chatIds, {Set<int>? mutedIds}) async {
    _ids
      ..clear()
      ..addAll(chatIds);
    if (mutedIds != null) {
      _mutedIds
        ..clear()
        ..addAll(mutedIds.where(_ids.contains));
    } else {
      _mutedIds.removeWhere((id) => !_ids.contains(id));
    }
    _pinnedIds.removeWhere((id) => !_ids.contains(id));
    _pickerCompleted = true;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _ids.map((id) => id.toString()).toList(),
    );
    await prefs.setStringList(
      _mutedKey,
      _mutedIds.map((id) => id.toString()).toList(),
    );
    await prefs.setStringList(
      _pinnedKey,
      _pinnedIds.map((id) => id.toString()).toList(),
    );
    await prefs.setBool(_onboardingKey, _pickerCompleted);
  }
}
