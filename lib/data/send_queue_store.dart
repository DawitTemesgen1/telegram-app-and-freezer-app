import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SendQueueKind {
  text,
  photo,
  video,
  audio,
  document,
  voice,
}

class SendQueueItem {
  const SendQueueItem({
    required this.id,
    required this.chatId,
    required this.kind,
    required this.pathOrText,
    this.replyToMessageId,
    this.caption,
    this.scheduleDate,
    this.entitiesJson,
    this.durationSeconds,
  });

  final String id;
  final int chatId;
  final SendQueueKind kind;
  final String pathOrText;
  final int? replyToMessageId;
  final String? caption;
  final int? scheduleDate;
  final String? entitiesJson;
  final int? durationSeconds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'kind': kind.name,
        'pathOrText': pathOrText,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (caption != null) 'caption': caption,
        if (scheduleDate != null) 'scheduleDate': scheduleDate,
        if (entitiesJson != null) 'entitiesJson': entitiesJson,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
      };

  static SendQueueItem? fromJson(Map<String, dynamic> json) {
    final kind = SendQueueKind.values
        .cast<SendQueueKind?>()
        .firstWhere(
          (k) => k?.name == json['kind'],
          orElse: () => null,
        );
    if (kind == null) return null;
    return SendQueueItem(
      id: '${json['id']}',
      chatId: int.tryParse('${json['chatId']}') ?? 0,
      kind: kind,
      pathOrText: '${json['pathOrText'] ?? ''}',
      replyToMessageId: int.tryParse('${json['replyToMessageId']}'),
      caption: json['caption'] as String?,
      scheduleDate: int.tryParse('${json['scheduleDate']}'),
      entitiesJson: json['entitiesJson'] as String?,
      durationSeconds: int.tryParse('${json['durationSeconds']}'),
    );
  }
}

/// Durable queue for failed outgoing messages; flushed when TDLib is ready.
class SendQueueStore extends ChangeNotifier {
  static const _key = 'send_queue_v1';

  final List<SendQueueItem> _items = [];
  bool _loaded = false;
  int _idCounter = 0;

  bool get isLoaded => _loaded;
  List<SendQueueItem> get items => List.unmodifiable(_items);
  int get pendingCount => _items.length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    _items.clear();
    for (final line in raw) {
      try {
        final map = jsonDecode(line);
        if (map is Map<String, dynamic>) {
          final item = SendQueueItem.fromJson(map);
          if (item != null && item.chatId != 0) _items.add(item);
        }
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> enqueue(SendQueueItem item) async {
    _items.add(item);
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _items.map((i) => jsonEncode(i.toJson())).toList(),
    );
  }

  String nextId() {
    _idCounter += 1;
    return '${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }
}
