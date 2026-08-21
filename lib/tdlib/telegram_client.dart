import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart' as td;
import 'package:tdlib/tdlib.dart';

import '../config.dart';
import '../data/chat_prefs_store.dart';
import '../data/send_queue_store.dart';
import '../utils/text_entities.dart';
import 'focus_chat.dart';
import 'focus_message_entities.dart';
import 'tdlib_path.dart';
import 'tdlib_receive_isolate.dart';

typedef NewMessageHandler = void Function(FocusChat chat, FocusMessage message);

enum TdConnectionState {
  ready,
  connecting,
  waitingForNetwork,
  updating,
  closed,
}

class TelegramClient extends ChangeNotifier {
  int _clientId = 0;
  Isolate? _receiveIsolate;
  ReceivePort? _receivePort;
  StreamSubscription? _receiveSub;
  bool _tdlibParametersSent = false;
  bool _recoveringBinlogLock = false;

  td.AuthorizationState? _authState;
  String? _lastError;
  bool _starting = false;
  bool _chatsLoaded = false;
  bool _loadingChats = false;

  final Map<int, FocusChat> _chats = {};
  final Map<int, List<FocusMessage>> _messagesByChat = {};
  final Map<int, String> _userNames = {};
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Set<int> _openChatIds = {};
  final Set<int> _loadingOlder = {};
  final Set<int> _loadingHistory = {};
  final Map<int, bool> _historyExhausted = {};
  final Map<int, String> _typingByChat = {};
  final Map<int, String> _userStatusLabel = {};
  int _extraCounter = 1;
  int? _myUserId;
  SendQueueStore? _sendQueue;
  bool _flushingQueue = false;
  TdConnectionState _connectionState = TdConnectionState.connecting;
  final Map<int, double> _fileDownloadProgress = {};
  final Map<int, FocusMessage?> _pinnedMessageByChat = {};
  final Map<int, String> _chatPhotoPaths = {};
  final Set<int> _fetchingChatPhotos = {};
  Timer? _backgroundSyncTimer;
  ChatPrefsStore? _chatPrefs;

  NewMessageHandler? onNewIncomingMessage;

  void attachSendQueue(SendQueueStore store) => _sendQueue = store;
  void attachChatPrefs(ChatPrefsStore store) => _chatPrefs = store;

  TdConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == TdConnectionState.ready;

  double? fileDownloadProgress(int fileId) => _fileDownloadProgress[fileId];

  /// Local path for a downloaded chat photo, if available.
  String? chatPhotoPath(int chatId) => _chatPhotoPaths[chatId];

  FocusMessage? pinnedMessageFor(int chatId) => _pinnedMessageByChat[chatId];

  td.AuthorizationState? get authState => _authState;
  String? get lastError => _lastError;
  bool get isReady => _authState is td.AuthorizationStateReady;
  bool get chatsLoaded => _chatsLoaded;
  bool get isLoadingChats => _loadingChats;
  int get knownChatCount => _chats.length;

  List<FocusChat> get allGroupChats {
    final list = _chats.values.where((c) => c.isGroupOrChannel).toList();
    list.sort((a, b) => b.lastMessageDate.compareTo(a.lastMessageDate));
    return list;
  }

  List<FocusChat> followedChats(Set<int> followedIds, {List<int> pinnedIds = const []}) {
    final list = followedIds
        .map((id) => _chats[id])
        .whereType<FocusChat>()
        .where((c) => c.isGroupOrChannel)
        .toList();
    final pinRank = <int, int>{
      for (var i = 0; i < pinnedIds.length; i++) pinnedIds[i]: i,
    };
    list.sort((a, b) {
      final aPinned = pinRank.containsKey(a.id);
      final bPinned = pinRank.containsKey(b.id);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      if (aPinned && bPinned) {
        return pinRank[a.id]!.compareTo(pinRank[b.id]!);
      }
      return b.lastMessageDate.compareTo(a.lastMessageDate);
    });
    return list;
  }

  FocusChat? chatById(int id) => _chats[id];

  String? userName(int userId) => _userNames[userId];
  int? get myUserId => _myUserId;

  List<FocusMessage> messagesFor(int chatId) =>
      List.unmodifiable(_messagesByChat[chatId] ?? const []);

  String? typingLabel(int chatId) => _typingByChat[chatId];

  String presenceSubtitle(int chatId) {
    final typing = _typingByChat[chatId];
    if (typing != null && typing.isNotEmpty) return typing;
    final chat = _chats[chatId];
    if (chat == null) return '';
    if (chat.kind == 'channel') return 'Channel';
    if (chat.kind == 'group') return 'Group';
    // Private: try cached user status from chat id mapping if any.
    return _userStatusLabel[chatId] ?? '';
  }

  Future<void> start() async {
    if (_starting || _clientId != 0) return;
    _starting = true;

    if (!AppConfig.hasCredentials) {
      _lastError =
          'Set TELEGRAM_API_ID and TELEGRAM_API_HASH in the .env file (see .env.example).';
      _starting = false;
      notifyListeners();
      return;
    }

    final tdlibPath = resolveTdlibPath();
    try {
      await TdPlugin.initialize(tdlibPath);
    } catch (e) {
      _lastError =
          'Failed to load TDLib ($tdlibPath). On Linux, place libtdjson.so in linux/libs/. Details: $e';
      _starting = false;
      notifyListeners();
      return;
    }

    // Stop any receive isolate left from a previous hot-restart session.
    await stopExistingTdlibReceiveIsolate();
    await _tearDownReceiveLoop();

    await _startReceiveLoop(tdlibPath);

    // Hot restart leaves native TDLib clients alive and holding td.binlog.
    await _closeOrphanedClients(probeRange: false);

    _clientId = tdCreate();
    await _persistActiveClientId(_clientId);
    tdSend(_clientId, const td.GetAuthorizationState());
    _starting = false;
    notifyListeners();
  }

  /// Closes native TDLib clients left over from a previous Dart isolate.
  /// Must run while the single receive loop is already active (never spawn
  /// a second receive isolate — TDLib forbids concurrent td_receive).
  Future<void> _closeOrphanedClients({required bool probeRange}) async {
    final staleIds = await _readPersistedClientIds();
    if (probeRange) {
      for (var id = 1; id <= 32; id++) {
        staleIds.add(id);
      }
    }
    if (staleIds.isEmpty) return;

    for (final id in staleIds) {
      if (id == _clientId) continue;
      try {
        tdSend(id, const td.Close());
      } catch (_) {}
    }

    // Let TDLib flush and unlock td.binlog on the existing receive thread.
    await Future<void>.delayed(
      Duration(milliseconds: probeRange ? 1500 : 350),
    );
    await _clearPersistedClientIds();
  }

  Future<File> _clientIdFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/tdlib/.tg_focus_client_ids');
  }

  Future<Set<int>> _readPersistedClientIds() async {
    try {
      final file = await _clientIdFile();
      if (!await file.exists()) return {};
      final lines = await file.readAsLines();
      return lines
          .map((line) => int.tryParse(line.trim()))
          .whereType<int>()
          .where((id) => id > 0)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistActiveClientId(int clientId) async {
    try {
      final file = await _clientIdFile();
      await file.parent.create(recursive: true);
      final ids = await _readPersistedClientIds()..add(clientId);
      await file.writeAsString(ids.map((id) => '$id').join('\n'));
    } catch (e) {
      debugPrint('Failed to persist TDLib client id: $e');
    }
  }

  Future<void> _clearPersistedClientIds() async {
    try {
      final file = await _clientIdFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _startReceiveLoop(String? tdlibPath) async {
    if (_receiveIsolate != null) return;
    _receivePort = ReceivePort();
    _receiveIsolate = await Isolate.spawn(
      tdlibReceiveIsolateMain,
      <dynamic>[_receivePort!.sendPort, tdlibPath],
      debugName: 'tdlib-receive',
      errorsAreFatal: false,
    );
    _receiveSub = _receivePort!.listen((event) {
      if (event is Map && event['error'] != null) {
        _lastError = 'TDLib receive failed: ${event['error']}';
        notifyListeners();
        return;
      }
      if (event is! String) return;
      _handleRaw(event);
    });
  }

  Future<Map<String, dynamic>> _send(td.TdFunction function) {
    final extra = _extraCounter++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[extra] = completer;
    tdSend(_clientId, function, extra);
    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _pending.remove(extra);
        return <String, dynamic>{
          '@type': 'error',
          'code': 408,
          'message': 'Request timed out',
        };
      },
    );
  }

  void _handleRaw(String raw) {
    final map = FocusChat.decodeMap(raw);
    if (map == null) return;

    final extra = map['@extra'];
    if (extra != null) {
      final completer = _pending.remove(extra);
      if (completer != null && !completer.isCompleted) {
        completer.complete(map);
      }
    }

    final type = map['@type'] as String? ?? '';

    switch (type) {
      case 'updateAuthorizationState':
        _handleAuthMap(map['authorization_state']);
        return;
      case 'authorizationStateWaitTdlibParameters':
      case 'authorizationStateWaitPhoneNumber':
      case 'authorizationStateWaitCode':
      case 'authorizationStateWaitPassword':
      case 'authorizationStateWaitRegistration':
      case 'authorizationStateWaitOtherDeviceConfirmation':
      case 'authorizationStateReady':
      case 'authorizationStateLoggingOut':
      case 'authorizationStateClosing':
      case 'authorizationStateClosed':
        _handleAuthMap(map);
        return;
      case 'updateNewChat':
        final chat = map['chat'];
        if (chat is Map<String, dynamic>) {
          final parsed = FocusChat.tryParse(chat);
          if (parsed != null) {
            _upsertChat(parsed);
            notifyListeners();
          }
        }
        return;
      case 'updateChatPhoto':
        final id = FocusChat.asInt(map['chat_id']);
        final existing = _chats[id];
        if (existing != null) {
          final fileId = FocusChat.photoFileIdFromJson(map['photo']);
          _chats[id] = existing.copyWith(
            photoFileId: fileId,
            clearPhotoFileId: fileId == null,
          );
          if (fileId == null) {
            _chatPhotoPaths.remove(id);
          } else {
            _chatPhotoPaths.remove(id);
            _maybeFetchChatPhoto(_chats[id]!);
          }
          notifyListeners();
        }
        return;
      case 'updateChatTitle':
        final id = FocusChat.asInt(map['chat_id']);
        final existing = _chats[id];
        if (existing != null) {
          _chats[id] = existing.copyWith(title: '${map['title'] ?? existing.title}');
          notifyListeners();
        }
        return;
      case 'updateChatLastMessage':
        final id = FocusChat.asInt(map['chat_id']);
        final existing = _chats[id];
        final last = map['last_message'];
        if (existing != null && last is Map<String, dynamic>) {
          _chats[id] = existing.copyWith(
            lastPreview: FocusChat.previewFromContent(last['content']),
            lastMessageDate: FocusChat.asInt(last['date']),
          );
          notifyListeners();
        }
        return;
      case 'updateChatReadInbox':
        final id = FocusChat.asInt(map['chat_id']);
        final existing = _chats[id];
        if (existing != null) {
          _chats[id] = existing.copyWith(
            unreadCount: FocusChat.asInt(map['unread_count']),
          );
          notifyListeners();
        }
        return;
      case 'updateNewMessage':
        _handleNewMessageMap(map['message']);
        return;
      case 'updateMessageContent':
        _handleMessageContentUpdate(map);
        return;
      case 'updateMessageInteractionInfo':
        _handleMessageInteractionUpdate(map);
        return;
      case 'updateDeleteMessages':
        _handleDeleteMessagesUpdate(map);
        return;
      case 'updateChatAction':
        _handleChatAction(map);
        return;
      case 'updateUserStatus':
        _handleUserStatus(map);
        return;
      case 'updateConnectionState':
        _handleConnectionState(map);
        return;
      case 'updateFile':
        _handleFileUpdate(map);
        return;
      case 'updateChatPinnedMessage':
        _handleChatPinnedUpdate(map);
        return;
      case 'updateChatIsMarkedAsUnread':
        _handleChatMarkedUnreadUpdate(map);
        return;
      case 'error':
        if (extra == null && FocusChat.asInt(map['code']) != 404) {
          _lastError = '${map['message']}';
          notifyListeners();
        }
        return;
      default:
        // Ignore other updates.
        return;
    }
  }

  void _handleChatAction(Map<String, dynamic> map) {
    final chatId = FocusChat.asInt(map['chat_id']);
    if (chatId == 0) return;
    final action = map['action'];
    final actionType =
        action is Map<String, dynamic> ? action['@type'] as String? : null;
    if (actionType == null || actionType == 'chatActionCancel') {
      if (_typingByChat.remove(chatId) != null) notifyListeners();
      return;
    }

    String label;
    switch (actionType) {
      case 'chatActionTyping':
        label = 'typing…';
        break;
      case 'chatActionRecordingVoiceNote':
        label = 'recording voice…';
        break;
      case 'chatActionUploadingPhoto':
        label = 'sending photo…';
        break;
      case 'chatActionUploadingVideo':
        label = 'sending video…';
        break;
      case 'chatActionUploadingDocument':
        label = 'sending file…';
        break;
      default:
        label = 'active…';
    }

    var who = 'Someone';
    final sender = map['sender_id'];
    if (sender is Map<String, dynamic>) {
      if (sender['@type'] == 'messageSenderUser') {
        final uid = FocusChat.asInt(sender['user_id']);
        who = _userNames[uid] ?? 'Someone';
        if (!_userNames.containsKey(uid) && uid != 0) {
          unawaited(_ensureUserName(uid));
        }
      } else if (sender['@type'] == 'messageSenderChat') {
        final cid = FocusChat.asInt(sender['chat_id']);
        who = _chats[cid]?.title ?? 'Someone';
      }
    }
    _typingByChat[chatId] = '$who is $label';
    notifyListeners();
    // Auto-clear stale typing after a few seconds.
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (_typingByChat[chatId]?.endsWith(label) == true) {
        _typingByChat.remove(chatId);
        notifyListeners();
      }
    });
  }

  void _handleUserStatus(Map<String, dynamic> map) {
    final userId = FocusChat.asInt(map['user_id']);
    final status = map['status'];
    if (userId == 0 || status is! Map<String, dynamic>) return;
    final type = status['@type'] as String? ?? '';
    final label = switch (type) {
      'userStatusOnline' => 'online',
      'userStatusOffline' => 'last seen recently',
      'userStatusRecently' => 'last seen recently',
      'userStatusLastWeek' => 'last seen within a week',
      'userStatusLastMonth' => 'last seen within a month',
      _ => '',
    };
    if (label.isEmpty) {
      _userStatusLabel.remove(userId);
    } else {
      _userStatusLabel[userId] = label;
    }
    notifyListeners();
  }

  void _handleConnectionState(Map<String, dynamic> map) {
    final state = map['state'];
    if (state is! Map<String, dynamic>) return;
    final type = state['@type'] as String? ?? '';
    final parsed = switch (type) {
      'connectionStateReady' => TdConnectionState.ready,
      'connectionStateConnecting' => TdConnectionState.connecting,
      'connectionStateConnectingToProxy' => TdConnectionState.connecting,
      'connectionStateWaitingForNetwork' => TdConnectionState.waitingForNetwork,
      'connectionStateUpdating' => TdConnectionState.updating,
      _ => TdConnectionState.closed,
    };
    if (_connectionState != parsed) {
      _connectionState = parsed;
      notifyListeners();
    }
  }

  void _handleFileUpdate(Map<String, dynamic> map) {
    final file = map['file'];
    if (file is! Map<String, dynamic>) return;
    final id = FocusChat.asInt(file['id']);
    if (id == 0) return;
    final local = file['local'];
    if (local is Map<String, dynamic>) {
      final downloaded = FocusChat.asInt(local['downloaded_size']);
      final total = FocusChat.asInt(file['size']);
      if (total > 0) {
        _fileDownloadProgress[id] = (downloaded / total).clamp(0.0, 1.0);
      } else if (local['is_downloading_completed'] == true) {
        _fileDownloadProgress[id] = 1.0;
      }
      if (local['is_downloading_completed'] == true) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          _fileDownloadProgress.remove(id);
          notifyListeners();
        });
      }
      notifyListeners();
    }
  }

  void _handleChatPinnedUpdate(Map<String, dynamic> map) {
    final chatId = FocusChat.asInt(map['chat_id']);
    final pinned = map['pinned_message'];
    if (chatId == 0) return;
    if (pinned is Map<String, dynamic>) {
      _pinnedMessageByChat[chatId] =
          FocusMessage.fromTdJson(pinned, myUserId: _myUserId);
    } else {
      _pinnedMessageByChat[chatId] = null;
    }
    notifyListeners();
  }

  void _handleChatMarkedUnreadUpdate(Map<String, dynamic> map) {
    final chatId = FocusChat.asInt(map['chat_id']);
    final marked = map['is_marked_as_unread'] == true;
    final existing = _chats[chatId];
    if (existing != null) {
      _chats[chatId] = existing.copyWith(isMarkedAsUnread: marked);
      notifyListeners();
    }
    if (!marked) {
      _chatPrefs?.setLocallyMarkedUnread(chatId, false);
    }
  }

  void _handleNewMessageMap(dynamic raw) {
    if (raw is! Map<String, dynamic>) return;
    final focusMessage = FocusMessage.fromTdJson(raw, myUserId: _myUserId);
    if (focusMessage == null) return;

    final list = _messagesByChat.putIfAbsent(focusMessage.chatId, () => []);
    var message = focusMessage;
    if (message.replyToMessageId != null && message.replyPreview == null) {
      final replied = _findMessage(list, message.replyToMessageId!);
      if (replied != null) {
        message = message.copyWith(replyPreview: replied.text);
      }
    }
    if (!list.any((m) => m.id == message.id)) {
      list.add(message);
      list.sort((a, b) => a.id.compareTo(b.id));
    }

    if (message.senderUserId != null) {
      unawaited(_ensureUserName(message.senderUserId!));
    }

    final chat = _chats[message.chatId];
    if (chat != null) {
      final isOpen = _openChatIds.contains(message.chatId);
      var unread = chat.unreadCount;
      if (!message.isOutgoing && !isOpen) {
        // Optimistic bump; updateChatReadInbox will correct when TDLib reports.
        unread = chat.unreadCount + 1;
        onNewIncomingMessage?.call(chat, message);
      }
      _chats[message.chatId] = chat.copyWith(
        lastPreview: message.text,
        lastMessageDate: message.date,
        unreadCount: isOpen ? 0 : unread,
      );
      if (isOpen && !message.isOutgoing) {
        unawaited(markChatRead(message.chatId));
      }
    }
    notifyListeners();
  }

  void _handleAuthMap(dynamic state) {
    if (state is! Map<String, dynamic>) return;
    final type = state['@type'] as String? ?? '';
    td.AuthorizationState? parsed;
    try {
      // Re-wrap so convertToObject can dispatch on @type.
      parsed = td.convertToObject(jsonEncode(state)) as td.AuthorizationState?;
    } catch (e) {
      debugPrint('Auth parse fallback for $type: $e');
      switch (type) {
        case 'authorizationStateWaitPhoneNumber':
          parsed = const td.AuthorizationStateWaitPhoneNumber();
          break;
        case 'authorizationStateWaitTdlibParameters':
          parsed = const td.AuthorizationStateWaitTdlibParameters();
          break;
        case 'authorizationStateReady':
          parsed = const td.AuthorizationStateReady();
          break;
        case 'authorizationStateWaitCode':
          // Enough for login UI; codeInfo details are unused by our screen.
          try {
            parsed = td.AuthorizationStateWaitCode.fromJson(state);
          } catch (_) {
            parsed = const td.AuthorizationStateWaitPhoneNumber();
          }
          break;
        case 'authorizationStateWaitPassword':
          try {
            parsed = td.AuthorizationStateWaitPassword.fromJson(state);
          } catch (_) {
            parsed = const td.AuthorizationStateWaitPassword(
              passwordHint: '',
              hasRecoveryEmailAddress: false,
              hasPassportData: false,
              recoveryEmailAddressPattern: '',
            );
          }
          break;
      }
    }
    if (parsed != null) {
      _applyAuthState(parsed);
    }
  }

  void _applyAuthState(td.AuthorizationState state) {
    final previous = _authState;
    _authState = state;
    notifyListeners();
    if (previous.runtimeType == state.runtimeType &&
        state is td.AuthorizationStateWaitTdlibParameters) {
      return;
    }
    unawaited(_onAuthState(state));
  }

  Future<void> _onAuthState(td.AuthorizationState state) async {
    if (state is td.AuthorizationStateWaitTdlibParameters) {
      if (_tdlibParametersSent) return;
      _tdlibParametersSent = true;

      final docs = await getApplicationDocumentsDirectory();
      final dbDir = Directory('${docs.path}/tdlib');
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      final result = await _send(
        td.SetTdlibParameters(
          useTestDc: false,
          databaseDirectory: dbDir.path,
          filesDirectory: dbDir.path,
          databaseEncryptionKey: '',
          useFileDatabase: true,
          useChatInfoDatabase: true,
          useMessageDatabase: true,
          useSecretChats: false,
          apiId: AppConfig.apiId,
          apiHash: AppConfig.apiHash,
          systemLanguageCode: Platform.localeName.split('_').first,
          deviceModel: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
          systemVersion: Platform.operatingSystemVersion,
          applicationVersion: '1.0.0',
          enableStorageOptimizer: true,
          ignoreFileNames: false,
        ),
      );
      if (result['@type'] == 'error') {
        final message = '${result['message']}';
        // Hot restart leaves a native client holding td.binlog.
        if (!_recoveringBinlogLock &&
            (message.contains('already in use') ||
                message.contains("Can't lock file"))) {
          _recoveringBinlogLock = true;
          _tdlibParametersSent = false;
          _lastError = null;
          notifyListeners();
          try {
            final oldId = _clientId;
            if (oldId != 0) {
              await _persistActiveClientId(oldId);
              try {
                tdSend(oldId, const td.Close());
              } catch (_) {}
              _clientId = 0;
            }
            // Keep the same receive isolate; only close stale native clients.
            await _closeOrphanedClients(probeRange: true);
            _clientId = tdCreate();
            await _persistActiveClientId(_clientId);
            tdSend(_clientId, const td.GetAuthorizationState());
          } finally {
            _recoveringBinlogLock = false;
          }
          return;
        }
        _tdlibParametersSent = false;
        _lastError = message;
        notifyListeners();
      } else {
        _lastError = null;
        notifyListeners();
      }
      return;
    }

    if (state is td.AuthorizationStateReady) {
      _lastError = null;
      await _ensureMe();
      await loadChats();
      await flushSendQueue();
      startBackgroundSync();
    }
  }

  Future<int?> _ensureMe() async {
    if (_myUserId != null) return _myUserId;
    final result = await _send(const td.GetMe());
    if (result['@type'] == 'user') {
      _myUserId = FocusChat.asInt(result['id']);
      notifyListeners();
      return _myUserId;
    }
    return null;
  }

  Future<void> flushSendQueue() async {
    final queue = _sendQueue;
    if (queue == null || !isReady || _flushingQueue) return;
    if (queue.items.isEmpty) return;
    _flushingQueue = true;
    try {
      for (final item in List<SendQueueItem>.from(queue.items)) {
        var ok = false;
        switch (item.kind) {
          case SendQueueKind.text:
            ok = await _sendTextInternal(
              item.chatId,
              item.pathOrText,
              replyToMessageId: item.replyToMessageId,
              scheduleDate: item.scheduleDate,
              enqueueOnError: false,
            );
            break;
          case SendQueueKind.photo:
            ok = await _sendMediaInternal(
              item.chatId,
              content: td.InputMessagePhoto(
                photo: td.InputFileLocal(path: item.pathOrText),
                addedStickerFileIds: const [],
                width: 0,
                height: 0,
                caption: _captionFormatted(item.caption),
                selfDestructTime: 0,
                hasSpoiler: false,
              ),
              preview: item.caption?.trim().isNotEmpty == true
                  ? item.caption!.trim()
                  : '[photo]',
              mediaKind: FocusMediaKind.photo,
              replyToMessageId: item.replyToMessageId,
              scheduleDate: item.scheduleDate,
              enqueueOnError: false,
            );
            break;
          case SendQueueKind.video:
            ok = await _sendMediaInternal(
              item.chatId,
              content: td.InputMessageVideo(
                video: td.InputFileLocal(path: item.pathOrText),
                addedStickerFileIds: const [],
                duration: 0,
                width: 0,
                height: 0,
                supportsStreaming: true,
                caption: _captionFormatted(item.caption),
                selfDestructTime: 0,
                hasSpoiler: false,
              ),
              preview: item.caption?.trim().isNotEmpty == true
                  ? item.caption!.trim()
                  : '[video]',
              mediaKind: FocusMediaKind.video,
              fileName: item.pathOrText.split(Platform.pathSeparator).last,
              replyToMessageId: item.replyToMessageId,
              scheduleDate: item.scheduleDate,
              enqueueOnError: false,
            );
            break;
          case SendQueueKind.audio:
            ok = await _sendMediaInternal(
              item.chatId,
              content: td.InputMessageAudio(
                audio: td.InputFileLocal(path: item.pathOrText),
                duration: 0,
                title: item.pathOrText.split(Platform.pathSeparator).last,
                performer: '',
                caption: _captionFormatted(item.caption),
              ),
              preview: '♫ ${item.pathOrText.split(Platform.pathSeparator).last}',
              mediaKind: FocusMediaKind.audio,
              fileName: item.pathOrText.split(Platform.pathSeparator).last,
              replyToMessageId: item.replyToMessageId,
              scheduleDate: item.scheduleDate,
              enqueueOnError: false,
            );
            break;
          case SendQueueKind.document:
            ok = await _sendMediaInternal(
              item.chatId,
              content: td.InputMessageDocument(
                document: td.InputFileLocal(path: item.pathOrText),
                disableContentTypeDetection: false,
                caption: _captionFormatted(item.caption),
              ),
              preview: item.pathOrText.split(Platform.pathSeparator).last,
              mediaKind: FocusMediaKind.file,
              fileName: item.pathOrText.split(Platform.pathSeparator).last,
              replyToMessageId: item.replyToMessageId,
              scheduleDate: item.scheduleDate,
              enqueueOnError: false,
            );
            break;
          case SendQueueKind.voice:
            ok = await _sendMediaInternal(
              item.chatId,
              content: td.InputMessageVoiceNote(
                voiceNote: td.InputFileLocal(path: item.pathOrText),
                duration: item.durationSeconds ?? 0,
                waveform: '',
              ),
              preview: '[voice]',
              mediaKind: FocusMediaKind.voice,
              replyToMessageId: item.replyToMessageId,
              scheduleDate: item.scheduleDate,
              enqueueOnError: false,
            );
            break;
        }
        if (ok) await queue.remove(item.id);
      }
    } finally {
      _flushingQueue = false;
    }
  }

  td.FormattedText? _captionFormatted(String? caption) {
    if (caption == null || caption.trim().isEmpty) return null;
    return buildFormattedText(caption.trim());
  }

  td.MessageSendOptions? _sendOptions({int? scheduleDate}) {
    if (scheduleDate == null || scheduleDate <= 0) return null;
    return td.MessageSendOptions(
      disableNotification: false,
      fromBackground: false,
      protectContent: false,
      updateOrderOfInstalledStickerSets: false,
      schedulingState: td.MessageSchedulingStateSendAtDate(
        sendDate: scheduleDate,
      ),
      sendingId: 0,
    );
  }

  Future<void> submitPhoneNumber(String phoneNumber) async {
    _lastError = null;
    notifyListeners();
    final result = await _send(
      td.SetAuthenticationPhoneNumber(
        phoneNumber: phoneNumber.trim(),
        settings: const td.PhoneNumberAuthenticationSettings(
          allowFlashCall: false,
          allowMissedCall: false,
          isCurrentPhoneNumber: false,
          allowSmsRetrieverApi: false,
          authenticationTokens: [],
        ),
      ),
    );
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
    }
  }

  Future<void> submitCode(String code) async {
    _lastError = null;
    notifyListeners();
    final result = await _send(td.CheckAuthenticationCode(code: code.trim()));
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
    }
  }

  Future<void> submitPassword(String password) async {
    _lastError = null;
    notifyListeners();
    final result =
        await _send(td.CheckAuthenticationPassword(password: password));
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
    }
  }

  void _upsertChat(FocusChat parsed) {
    _chats[parsed.id] = parsed;
    _maybeFetchChatPhoto(parsed);
  }

  Future<void> loadChats() async {
    if (_loadingChats) return;
    _loadingChats = true;
    _chatsLoaded = false;
    notifyListeners();

    // Ask TDLib to load dialogs into memory (emits updateNewChat).
    for (var i = 0; i < 30; i++) {
      final result = await _send(
        const td.LoadChats(
          chatList: td.ChatListMain(),
          limit: 100,
        ),
      );
      if (result['@type'] == 'error') {
        final code = FocusChat.asInt(result['code']);
        if (code == 404) break;
        // Keep going for transient errors.
      }
      // Give updates a moment to arrive between pages.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // Explicitly fetch chat IDs then each chat (version-tolerant JSON parse).
    final chatsResult = await _send(const td.GetChats(limit: 200));
    if (chatsResult['@type'] == 'chats') {
      final ids = (chatsResult['chat_ids'] as List? ?? const [])
          .map(FocusChat.asInt)
          .where((id) => id != 0)
          .toList();
      for (final id in ids) {
        final chatResult = await _send(td.GetChat(chatId: id));
        if (chatResult['@type'] == 'chat') {
          final parsed = FocusChat.tryParse(chatResult);
          if (parsed != null) {
            _upsertChat(parsed);
          }
        }
      }
    }

    _chatsLoaded = true;
    _loadingChats = false;
    notifyListeners();
  }

  Future<void> openChat(int chatId) async {
    _openChatIds.add(chatId);
    await _send(td.OpenChat(chatId: chatId));
    unawaited(loadPinnedMessage(chatId));
    unawaited(refreshChat(chatId));
    // Clear local unread immediately for snappy UI.
    final chat = _chats[chatId];
    if (chat != null && chat.unreadCount > 0) {
      _chats[chatId] = chat.copyWith(unreadCount: 0, isMarkedAsUnread: false);
      await _chatPrefs?.setLocallyMarkedUnread(chatId, false);
      notifyListeners();
    }
  }

  Future<void> closeChat(int chatId) async {
    _openChatIds.remove(chatId);
    await _send(td.CloseChat(chatId: chatId));
  }

  Future<void> markChatRead(int chatId) async {
    final list = _messagesByChat[chatId];
    final chat = _chats[chatId];
    if (chat != null && chat.unreadCount > 0) {
      _chats[chatId] = chat.copyWith(unreadCount: 0);
      notifyListeners();
    }
    if (list == null || list.isEmpty) return;
    // Only the newest few ids — enough for force-read, much faster.
    final ids = list.length <= 12
        ? list.map((m) => m.id).toList()
        : list.sublist(list.length - 12).map((m) => m.id).toList();
    unawaited(
      _send(
        td.ViewMessages(
          chatId: chatId,
          messageIds: ids,
          forceRead: true,
        ),
      ),
    );
  }

  Future<String?> _ensureUserName(int userId) async {
    final cached = _userNames[userId];
    if (cached != null) return cached;
    // Avoid stampeding GetUser during history load.
    if (_userNames.containsKey(userId)) return _userNames[userId];
    _userNames[userId] = '…';
    final result = await _send(td.GetUser(userId: userId));
    if (result['@type'] != 'user') {
      _userNames.remove(userId);
      return null;
    }
    final first = '${result['first_name'] ?? ''}'.trim();
    final last = '${result['last_name'] ?? ''}'.trim();
    var username = '${result['username'] ?? ''}'.trim();
    final usernames = result['usernames'];
    if (username.isEmpty && usernames is Map<String, dynamic>) {
      username = '${usernames['editable_username'] ?? ''}'.trim();
    }
    final name = ('$first $last').trim();
    final display = name.isNotEmpty
        ? name
        : (username.isNotEmpty ? '@$username' : 'User $userId');
    _userNames[userId] = display;
    notifyListeners();
    return display;
  }

  String senderDisplayName(FocusMessage message) {
    if (message.senderName != null && message.senderName!.isNotEmpty) {
      return message.senderName!;
    }
    final userId = message.senderUserId;
    if (userId != null) {
      return _userNames[userId] ?? 'Member';
    }
    if (message.senderChatId != null) {
      return _chats[message.senderChatId!]?.title ?? 'Chat';
    }
    return 'Member';
  }

  Future<void> loadChatHistory(
    int chatId, {
    int fromMessageId = 0,
    bool markRead = true,
  }) async {
    final isInitial = fromMessageId == 0;
    if (isInitial) {
      _loadingHistory.add(chatId);
      notifyListeners();
    }

    try {
      // Show cached messages immediately when opening a chat.
      if (isInitial) {
        final local = await _send(
          td.GetChatHistory(
            chatId: chatId,
            fromMessageId: 0,
            offset: 0,
            limit: 40,
            onlyLocal: true,
          ),
        );
        _mergeHistory(chatId, local);
        notifyListeners();
      }

      final result = await _send(
        td.GetChatHistory(
          chatId: chatId,
          fromMessageId: fromMessageId,
          offset: 0,
          limit: isInitial ? 40 : 50,
          onlyLocal: false,
        ),
      );

      final beforeCount = _messagesByChat[chatId]?.length ?? 0;
      final added = _mergeHistory(chatId, result);
      final messages = result['messages'] as List? ?? const [];

      if (markRead) {
        markChatRead(chatId);
      }
      if (!isInitial) {
        _historyExhausted[chatId] = messages.isEmpty || added == 0;
      } else if (messages.isEmpty && beforeCount == 0) {
        _historyExhausted[chatId] = true;
      }
      notifyListeners();
    } finally {
      if (isInitial) {
        _loadingHistory.remove(chatId);
        notifyListeners();
      }
    }
  }

  int _mergeHistory(int chatId, Map<String, dynamic> result) {
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      return 0;
    }
    if (result['@type'] != 'messages') return 0;

    final list = _messagesByChat.putIfAbsent(chatId, () => []);
    var added = 0;
    final messages = result['messages'] as List? ?? const [];
    final pendingUsers = <int>{};
    for (final item in messages) {
      if (item is! Map<String, dynamic>) continue;
      final msg = FocusMessage.fromTdJson(item, myUserId: _myUserId);
      if (msg == null) continue;
      if (!list.any((m) => m.id == msg.id)) {
        list.add(msg);
        added++;
      }
      if (msg.senderUserId != null &&
          !_userNames.containsKey(msg.senderUserId)) {
        pendingUsers.add(msg.senderUserId!);
      }
    }
    list.sort((a, b) => a.id.compareTo(b.id));

    for (var i = 0; i < list.length; i++) {
      final msg = list[i];
      if (msg.replyToMessageId == null || msg.replyPreview != null) continue;
      final replied = _findMessage(list, msg.replyToMessageId!);
      if (replied != null) {
        list[i] = msg.copyWith(replyPreview: replied.text);
      }
    }

    for (final userId in pendingUsers.take(12)) {
      unawaited(_ensureUserName(userId));
    }
    return added;
  }

  /// Load older messages above the current oldest. Returns how many were added.
  Future<int> loadOlderMessages(int chatId) async {
    if (_historyExhausted[chatId] == true) return 0;
    if (_loadingOlder.contains(chatId)) return 0;
    final list = _messagesByChat[chatId];
    if (list == null || list.isEmpty) {
      await loadChatHistory(chatId);
      return messagesFor(chatId).length;
    }

    _loadingOlder.add(chatId);
    notifyListeners();
    final oldestId = list.first.id;
    final before = list.length;
    try {
      await loadChatHistory(chatId, fromMessageId: oldestId, markRead: false);
      return (_messagesByChat[chatId]?.length ?? before) - before;
    } finally {
      _loadingOlder.remove(chatId);
      notifyListeners();
    }
  }

  bool isLoadingOlder(int chatId) => _loadingOlder.contains(chatId);
  bool isLoadingHistory(int chatId) => _loadingHistory.contains(chatId);
  bool hasMoreHistory(int chatId) => _historyExhausted[chatId] != true;

  Future<List<FocusMessage>> searchChatMessages(
    int chatId,
    String query,
  ) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final result = await _send(
      td.SearchChatMessages(
        chatId: chatId,
        query: trimmed,
        fromMessageId: 0,
        offset: 0,
        limit: 40,
        messageThreadId: 0,
      ),
    );

    if (result['@type'] != 'foundChatMessages' &&
        result['@type'] != 'foundMessages' &&
        result['@type'] != 'messages') {
      if (result['@type'] == 'error') {
        _lastError = '${result['message']}';
        notifyListeners();
      }
      return const [];
    }

    final messages = result['messages'] as List? ?? const [];
    final found = <FocusMessage>[];
    for (final item in messages) {
      if (item is! Map<String, dynamic>) continue;
      final msg = FocusMessage.fromTdJson(item, myUserId: _myUserId);
      if (msg == null) continue;
      found.add(msg);
      if (msg.senderUserId != null) {
        unawaited(_ensureUserName(msg.senderUserId!));
      }
    }
    return found;
  }

  Future<String?> downloadPhoto(int fileId) => downloadFile(fileId);

  void _maybeFetchChatPhoto(FocusChat chat) {
    final fileId = chat.photoFileId;
    if (fileId == null) return;
    if (_chatPhotoPaths.containsKey(chat.id)) return;
    if (_fetchingChatPhotos.contains(chat.id)) return;
    unawaited(ensureChatPhoto(chat.id));
  }

  /// Downloads (or reuses) the small chat photo and caches the local path.
  Future<String?> ensureChatPhoto(int chatId) async {
    final existingPath = _chatPhotoPaths[chatId];
    if (existingPath != null && File(existingPath).existsSync()) {
      return existingPath;
    }
    final chat = _chats[chatId];
    final fileId = chat?.photoFileId;
    if (fileId == null) return null;
    if (_fetchingChatPhotos.contains(chatId)) return existingPath;
    _fetchingChatPhotos.add(chatId);
    try {
      final path = await downloadFile(fileId);
      if (path != null && path.isNotEmpty) {
        _chatPhotoPaths[chatId] = path;
        notifyListeners();
        return path;
      }
    } finally {
      _fetchingChatPhotos.remove(chatId);
    }
    return null;
  }

  Future<String?> downloadFile(int fileId) async {
    _fileDownloadProgress[fileId] = 0;
    notifyListeners();
    final result = await _send(
      td.DownloadFile(
        fileId: fileId,
        priority: 16,
        offset: 0,
        limit: 0,
        synchronous: false,
      ),
    );
    if (result['@type'] == 'file') {
      final local = result['local'];
      if (local is Map<String, dynamic>) {
        final path = '${local['path'] ?? ''}';
        if (local['is_downloading_completed'] == true && path.isNotEmpty) {
          _fileDownloadProgress[fileId] = 1.0;
          notifyListeners();
          return path;
        }
        // Poll until complete (updateFile also tracks progress).
        for (var i = 0; i < 120; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          final info = await _send(td.GetFile(fileId: fileId));
          if (info['@type'] == 'file') {
            final loc = info['local'];
            if (loc is Map<String, dynamic>) {
              final p = '${loc['path'] ?? ''}';
              if (loc['is_downloading_completed'] == true && p.isNotEmpty) {
                _fileDownloadProgress[fileId] = 1.0;
                notifyListeners();
                return p;
              }
            }
          }
        }
      }
    } else if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      _fileDownloadProgress.remove(fileId);
      notifyListeners();
    }
    return null;
  }

  Future<void> sendTyping(int chatId) async {
    unawaited(
      _send(
        td.SendChatAction(
          chatId: chatId,
          messageThreadId: 0,
          action: const td.ChatActionTyping(),
        ),
      ),
    );
  }

  Future<void> sendPhotoFile(
    int chatId,
    String path, {
    int? replyToMessageId,
    String? caption,
    int? scheduleDate,
  }) async {
    await _sendMedia(
      chatId,
      replyToMessageId: replyToMessageId,
      scheduleDate: scheduleDate,
      content: td.InputMessagePhoto(
        photo: td.InputFileLocal(path: path),
        addedStickerFileIds: const [],
        width: 0,
        height: 0,
        caption: _captionFormatted(caption),
        selfDestructTime: 0,
        hasSpoiler: false,
      ),
      preview: caption?.trim().isNotEmpty == true ? caption!.trim() : '[photo]',
      mediaKind: FocusMediaKind.photo,
    );
  }

  Future<void> sendVideoFile(
    int chatId,
    String path, {
    int? replyToMessageId,
    String? caption,
    int? scheduleDate,
  }) async {
    await _sendMedia(
      chatId,
      replyToMessageId: replyToMessageId,
      scheduleDate: scheduleDate,
      content: td.InputMessageVideo(
        video: td.InputFileLocal(path: path),
        addedStickerFileIds: const [],
        duration: 0,
        width: 0,
        height: 0,
        supportsStreaming: true,
        caption: _captionFormatted(caption),
        selfDestructTime: 0,
        hasSpoiler: false,
      ),
      preview: caption?.trim().isNotEmpty == true ? caption!.trim() : '[video]',
      mediaKind: FocusMediaKind.video,
      fileName: path.split(Platform.pathSeparator).last,
    );
  }

  Future<void> sendAudioFile(
    int chatId,
    String path, {
    int? replyToMessageId,
    String? caption,
    int? scheduleDate,
  }) async {
    final name = path.split(Platform.pathSeparator).last;
    await _sendMedia(
      chatId,
      replyToMessageId: replyToMessageId,
      scheduleDate: scheduleDate,
      content: td.InputMessageAudio(
        audio: td.InputFileLocal(path: path),
        duration: 0,
        title: name,
        performer: '',
        caption: _captionFormatted(caption),
      ),
      preview: '♫ $name',
      mediaKind: FocusMediaKind.audio,
      fileName: name,
    );
  }

  Future<void> sendDocumentFile(
    int chatId,
    String path, {
    int? replyToMessageId,
    String? caption,
    int? scheduleDate,
  }) async {
    final name = path.split(Platform.pathSeparator).last;
    await _sendMedia(
      chatId,
      replyToMessageId: replyToMessageId,
      scheduleDate: scheduleDate,
      content: td.InputMessageDocument(
        document: td.InputFileLocal(path: path),
        disableContentTypeDetection: false,
        caption: _captionFormatted(caption),
      ),
      preview: name,
      mediaKind: FocusMediaKind.file,
      fileName: name,
    );
  }

  Future<void> sendVoiceNote(
    int chatId,
    String path, {
    int durationSeconds = 0,
    int? replyToMessageId,
    int? scheduleDate,
  }) async {
    await _sendMedia(
      chatId,
      replyToMessageId: replyToMessageId,
      scheduleDate: scheduleDate,
      content: td.InputMessageVoiceNote(
        voiceNote: td.InputFileLocal(path: path),
        duration: durationSeconds,
        waveform: '',
      ),
      preview: '[voice]',
      mediaKind: FocusMediaKind.voice,
      durationSeconds: durationSeconds,
    );
  }

  Future<void> _sendMedia(
    int chatId, {
    required td.InputMessageContent content,
    required String preview,
    required FocusMediaKind mediaKind,
    String? fileName,
    int? replyToMessageId,
    int? scheduleDate,
    int? durationSeconds,
  }) async {
    await _sendMediaInternal(
      chatId,
      content: content,
      preview: preview,
      mediaKind: mediaKind,
      fileName: fileName,
      replyToMessageId: replyToMessageId,
      scheduleDate: scheduleDate,
      durationSeconds: durationSeconds,
    );
  }

  Future<bool> _sendMediaInternal(
    int chatId, {
    required td.InputMessageContent content,
    required String preview,
    required FocusMediaKind mediaKind,
    String? fileName,
    int? replyToMessageId,
    int? scheduleDate,
    int? durationSeconds,
    bool enqueueOnError = true,
  }) async {
    final replyPreview = replyToMessageId == null
        ? null
        : _findMessage(_messagesByChat[chatId] ?? const [], replyToMessageId)
            ?.text;

    final result = await _send(
      td.SendMessage(
        chatId: chatId,
        messageThreadId: 0,
        replyTo: replyToMessageId == null
            ? null
            : td.MessageReplyToMessage(
                chatId: chatId,
                messageId: replyToMessageId,
              ),
        options: _sendOptions(scheduleDate: scheduleDate),
        inputMessageContent: content,
      ),
    );

    if (result['@type'] == 'message') {
      final parsed = FocusMessage.fromTdJson(result, myUserId: _myUserId) ??
          FocusMessage(
            id: FocusChat.asInt(result['id']),
            chatId: chatId,
            text: preview,
            date: FocusChat.asInt(result['date']),
            isOutgoing: true,
            replyToMessageId: replyToMessageId,
            replyPreview: replyPreview,
            mediaKind: mediaKind,
            fileName: fileName,
            durationSeconds: durationSeconds,
          );
      _upsertMessage(parsed);
      final chat = _chats[chatId];
      if (chat != null) {
        _chats[chatId] = chat.copyWith(
          lastPreview: preview,
          lastMessageDate: parsed.date,
        );
      }
      notifyListeners();
      return true;
    }
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
      if (enqueueOnError) {
        await _enqueueFailedMedia(
          chatId,
          content,
          preview,
          mediaKind,
          fileName: fileName,
          replyToMessageId: replyToMessageId,
          scheduleDate: scheduleDate,
          durationSeconds: durationSeconds,
        );
      }
    }
    return false;
  }

  Future<void> _enqueueFailedMedia(
    int chatId,
    td.InputMessageContent content,
    String preview,
    FocusMediaKind mediaKind, {
    String? fileName,
    int? replyToMessageId,
    int? scheduleDate,
    int? durationSeconds,
  }) async {
    final queue = _sendQueue;
    if (queue == null) return;
    String? path;
    SendQueueKind kind;
    if (content is td.InputMessagePhoto) {
      kind = SendQueueKind.photo;
      path = (content.photo as td.InputFileLocal?)?.path;
    } else if (content is td.InputMessageVideo) {
      kind = SendQueueKind.video;
      path = (content.video as td.InputFileLocal?)?.path;
    } else if (content is td.InputMessageAudio) {
      kind = SendQueueKind.audio;
      path = (content.audio as td.InputFileLocal?)?.path;
    } else if (content is td.InputMessageDocument) {
      kind = SendQueueKind.document;
      path = (content.document as td.InputFileLocal?)?.path;
    } else if (content is td.InputMessageVoiceNote) {
      kind = SendQueueKind.voice;
      path = (content.voiceNote as td.InputFileLocal?)?.path;
    } else {
      return;
    }
    if (path == null || path.isEmpty) return;
    await queue.enqueue(
      SendQueueItem(
        id: queue.nextId(),
        chatId: chatId,
        kind: kind,
        pathOrText: path,
        replyToMessageId: replyToMessageId,
        caption: preview.startsWith('[') ? null : preview,
        scheduleDate: scheduleDate,
        durationSeconds: durationSeconds,
      ),
    );
  }

  Future<void> markAllFollowedRead(Set<int> followedIds) async {
    for (final chatId in followedIds) {
      final chat = _chats[chatId];
      if (chat == null || chat.unreadCount <= 0) continue;
      await markChatRead(chatId);
    }
  }

  Future<void> sendText(
    int chatId,
    String text, {
    int? replyToMessageId,
    int? scheduleDate,
    bool useFormatting = true,
  }) async {
    await _sendTextInternal(
      chatId,
      text,
      replyToMessageId: replyToMessageId,
      scheduleDate: scheduleDate,
      useFormatting: useFormatting,
    );
  }

  Future<bool> _sendTextInternal(
    int chatId,
    String text, {
    int? replyToMessageId,
    int? scheduleDate,
    bool useFormatting = true,
    bool enqueueOnError = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final formatted =
        useFormatting ? buildFormattedText(trimmed) : td.FormattedText(text: trimmed, entities: const []);
    final replyPreview = replyToMessageId == null
        ? null
        : _findMessage(_messagesByChat[chatId] ?? const [], replyToMessageId)
            ?.text;

    final result = await _send(
      td.SendMessage(
        chatId: chatId,
        messageThreadId: 0,
        replyTo: replyToMessageId == null
            ? null
            : td.MessageReplyToMessage(
                chatId: chatId,
                messageId: replyToMessageId,
              ),
        options: _sendOptions(scheduleDate: scheduleDate),
        inputMessageContent: td.InputMessageText(
          text: formatted,
          disableWebPagePreview: false,
          clearDraft: true,
        ),
      ),
    );

    if (result['@type'] == 'message') {
      final msg = FocusMessage.fromTdJson(result, myUserId: _myUserId) ??
          FocusMessage(
            id: FocusChat.asInt(result['id']),
            chatId: chatId,
            text: formatted.text,
            date: FocusChat.asInt(result['date']),
            isOutgoing: true,
            replyToMessageId: replyToMessageId,
            replyPreview: replyPreview,
          );
      _upsertMessage(msg);
      final chat = _chats[chatId];
      if (chat != null) {
        _chats[chatId] = chat.copyWith(
          lastPreview: formatted.text,
          lastMessageDate: msg.date,
        );
      }
      notifyListeners();
      return true;
    }
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
      if (enqueueOnError) {
        final queue = _sendQueue;
        if (queue != null) {
          await queue.enqueue(
            SendQueueItem(
              id: queue.nextId(),
              chatId: chatId,
              kind: SendQueueKind.text,
              pathOrText: trimmed,
              replyToMessageId: replyToMessageId,
              scheduleDate: scheduleDate,
            ),
          );
        }
      }
    }
    return false;
  }

  Future<bool> editText(int chatId, int messageId, String text) async {
    final formatted = buildFormattedText(text.trim());
    final result = await _send(
      td.EditMessageText(
        chatId: chatId,
        messageId: messageId,
        inputMessageContent: td.InputMessageText(
          text: formatted,
          disableWebPagePreview: false,
          clearDraft: false,
        ),
      ),
    );
    if (result['@type'] == 'message') {
      final parsed = FocusMessage.fromTdJson(result, myUserId: _myUserId);
      if (parsed != null) _upsertMessage(parsed);
      notifyListeners();
      return true;
    }
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
    }
    return false;
  }

  Future<bool> deleteMessages(
    int chatId,
    List<int> messageIds, {
    bool revoke = true,
  }) async {
    if (messageIds.isEmpty) return false;
    final result = await _send(
      td.DeleteMessages(
        chatId: chatId,
        messageIds: messageIds,
        revoke: revoke,
      ),
    );
    if (result['@type'] == 'ok') {
      final list = _messagesByChat[chatId];
      if (list != null) {
        list.removeWhere((m) => messageIds.contains(m.id));
      }
      notifyListeners();
      return true;
    }
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
    }
    return false;
  }

  Future<bool> forwardMessages(
    int fromChatId,
    int toChatId,
    List<int> messageIds,
  ) async {
    if (messageIds.isEmpty) return false;
    final result = await _send(
      td.ForwardMessages(
        chatId: toChatId,
        messageThreadId: 0,
        fromChatId: fromChatId,
        messageIds: messageIds,
        sendCopy: false,
        removeCaption: false,
        onlyPreview: false,
      ),
    );
    if (result['@type'] == 'messages') {
      final messages = result['messages'] as List? ?? const [];
      for (final item in messages) {
        if (item is Map<String, dynamic>) {
          final parsed = FocusMessage.fromTdJson(item, myUserId: _myUserId);
          if (parsed != null) _upsertMessage(parsed);
        }
      }
      notifyListeners();
      return true;
    }
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
    }
    return false;
  }

  Future<bool> addReaction(int chatId, int messageId, String emoji) async {
    final result = await _send(
      td.AddMessageReaction(
        chatId: chatId,
        messageId: messageId,
        reactionType: td.ReactionTypeEmoji(emoji: emoji),
        isBig: false,
        updateRecentReactions: true,
      ),
    );
    if (result['@type'] == 'ok') return true;
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
    }
    return false;
  }

  Future<String?> getMessageLink(int chatId, int messageId) async {
    final result = await _send(
      td.GetMessageLink(
        chatId: chatId,
        messageId: messageId,
        mediaTimestamp: 0,
        forAlbum: false,
        inMessageThread: false,
      ),
    );
    if (result['@type'] == 'messageLink') {
      return result['link'] as String?;
    }
    if (result['@type'] == 'error') {
      _lastError = '${result['message']}';
      notifyListeners();
    }
    return null;
  }

  Future<List<({int userId, String name, String? username})>> searchChatMembers(
    int chatId,
    String query, {
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final result = await _send(
      td.SearchChatMembers(
        chatId: chatId,
        query: trimmed,
        limit: limit,
        filter: const td.ChatMembersFilterMembers(),
      ),
    );
    if (result['@type'] != 'chatMembers') {
      if (result['@type'] == 'error') {
        _lastError = '${result['message']}';
        notifyListeners();
      }
      return const [];
    }
    final members = result['members'] as List? ?? const [];
    final out = <({int userId, String name, String? username})>[];
    for (final member in members) {
      if (member is! Map<String, dynamic>) continue;
      final memberId = member['member_id'];
      if (memberId is! Map<String, dynamic>) continue;
      if (memberId['@type'] != 'messageSenderUser') continue;
      final userId = FocusChat.asInt(memberId['user_id']);
      if (userId == 0) continue;
      final userResult = await _send(td.GetUser(userId: userId));
      if (userResult['@type'] != 'user') continue;
      final first = '${userResult['first_name'] ?? ''}'.trim();
      final last = '${userResult['last_name'] ?? ''}'.trim();
      var username = '${userResult['username'] ?? ''}'.trim();
      final usernames = userResult['usernames'];
      if (username.isEmpty && usernames is Map<String, dynamic>) {
        username = '${usernames['editable_username'] ?? ''}'.trim();
      }
      final name = ('$first $last').trim();
      out.add((
        userId: userId,
        name: name.isNotEmpty ? name : (username.isNotEmpty ? '@$username' : 'User $userId'),
        username: username.isEmpty ? null : username,
      ));
      _userNames[userId] = name.isNotEmpty ? name : '@$username';
    }
    notifyListeners();
    return out;
  }

  void startBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!isReady) return;
      unawaited(_backgroundPing());
    });
  }

  Future<void> _backgroundPing() async {
    if (!isReady) return;
    await _send(
      const td.LoadChats(
        chatList: td.ChatListMain(),
        limit: 20,
      ),
    );
    for (final id in _openChatIds) {
      final result = await _send(td.GetChat(chatId: id));
      if (result['@type'] == 'chat') {
        final parsed = FocusChat.tryParse(result);
        if (parsed != null) _upsertChat(parsed);
      }
    }
    notifyListeners();
  }

  Future<void> refreshChat(int chatId) async {
    final result = await _send(td.GetChat(chatId: chatId));
    if (result['@type'] == 'chat') {
      final parsed = FocusChat.tryParse(result);
      if (parsed != null) {
        _upsertChat(parsed);
        notifyListeners();
      }
    }
    await loadPinnedMessage(chatId);
  }

  Future<void> loadPinnedMessage(int chatId) async {
    final result = await _send(td.GetChatPinnedMessage(chatId: chatId));
    if (result['@type'] == 'message') {
      _pinnedMessageByChat[chatId] =
          FocusMessage.fromTdJson(result, myUserId: _myUserId);
      notifyListeners();
    } else if (result['@type'] == 'error') {
      final code = FocusChat.asInt(result['code']);
      if (code == 404) {
        _pinnedMessageByChat[chatId] = null;
        notifyListeners();
      }
    }
  }

  Future<bool> toggleChatMarkedUnread(int chatId, {required bool marked}) async {
    final result = await _send(
      td.ToggleChatIsMarkedAsUnread(
        chatId: chatId,
        isMarkedAsUnread: marked,
      ),
    );
    if (result['@type'] == 'ok') {
      final chat = _chats[chatId];
      if (chat != null) {
        _chats[chatId] = chat.copyWith(isMarkedAsUnread: marked);
      }
      await _chatPrefs?.setLocallyMarkedUnread(chatId, marked);
      notifyListeners();
      return true;
    }
    // Fallback: local flag only.
    await _chatPrefs?.setLocallyMarkedUnread(chatId, marked);
    final chat = _chats[chatId];
    if (chat != null) {
      _chats[chatId] = chat.copyWith(
        isMarkedAsUnread: marked,
        unreadCount: marked ? chat.unreadCount.clamp(1, 999) : 0,
      );
    }
    notifyListeners();
    return false;
  }

  Future<int> getChatMemberCount(int chatId) async {
    final chat = _chats[chatId];
    if (chat == null) return 0;
    final full = await _send(td.GetChat(chatId: chatId));
    if (full['@type'] != 'chat') return chat.memberCount;
    final type = full['type'];
    if (type is! Map<String, dynamic>) return chat.memberCount;
    if (type['@type'] == 'chatTypeBasicGroup') {
      final gid = FocusChat.asInt(type['basic_group_id']);
      final bg = await _send(td.GetBasicGroupFullInfo(basicGroupId: gid));
      if (bg['@type'] == 'basicGroupFullInfo') {
        return FocusChat.asInt(bg['member_count']);
      }
    } else if (type['@type'] == 'chatTypeSupergroup') {
      final sid = FocusChat.asInt(type['supergroup_id']);
      final sg = await _send(td.GetSupergroupFullInfo(supergroupId: sid));
      if (sg['@type'] == 'supergroupFullInfo') {
        return FocusChat.asInt(sg['member_count']);
      }
    }
    return chat.memberCount;
  }

  Future<List<({int setId, String title})>> getInstalledStickerSets() async {
    final result = await _send(
      const td.GetInstalledStickerSets(
        stickerType: td.StickerTypeRegular(),
      ),
    );
    if (result['@type'] != 'stickerSets') return const [];
    final sets = result['sets'] as List? ?? const [];
    final out = <({int setId, String title})>[];
    for (final s in sets) {
      if (s is! Map<String, dynamic>) continue;
      final id = FocusChat.asInt(s['id']);
      final title = '${s['title'] ?? 'Stickers'}';
      if (id != 0) out.add((setId: id, title: title));
    }
    return out;
  }

  Future<List<({int stickerId, int fileId, String emoji, int width, int height})>>
      getStickersInSet(int setId) async {
    final result = await _send(td.GetStickerSet(setId: setId));
    if (result['@type'] != 'stickerSet') return const [];
    final stickers = result['stickers'] as List? ?? const [];
    final out =
        <({int stickerId, int fileId, String emoji, int width, int height})>[];
    for (final s in stickers) {
      if (s is! Map<String, dynamic>) continue;
      final stickerId = FocusChat.asInt(s['id']);
      final emoji = '${s['emoji'] ?? '🙂'}';
      final width = FocusChat.asInt(s['width']);
      final height = FocusChat.asInt(s['height']);
      final fileObj = s['sticker'];
      if (fileObj is Map<String, dynamic>) {
        final fid = FocusChat.asInt(fileObj['id']);
        if (fid != 0) {
          out.add((
            stickerId: stickerId,
            fileId: fid,
            emoji: emoji,
            width: width <= 0 ? 512 : width,
            height: height <= 0 ? 512 : height,
          ));
        }
      }
    }
    return out;
  }

  Future<bool> sendSticker(
    int chatId,
    int stickerFileId, {
    required String emoji,
    int width = 512,
    int height = 512,
    int? replyToMessageId,
  }) async {
    final result = await _send(
      td.SendMessage(
        chatId: chatId,
        messageThreadId: 0,
        replyTo: replyToMessageId == null
            ? null
            : td.MessageReplyToMessage(
                chatId: chatId,
                messageId: replyToMessageId,
              ),
        options: null,
        inputMessageContent: td.InputMessageSticker(
          sticker: td.InputFileId(id: stickerFileId),
          width: width,
          height: height,
          emoji: emoji,
        ),
      ),
    );
    if (result['@type'] == 'message') {
      final parsed = FocusMessage.fromTdJson(result, myUserId: _myUserId);
      if (parsed != null) _upsertMessage(parsed);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> retryQueueItem(SendQueueItem item) async {
    final queue = _sendQueue;
    if (queue == null) return false;
    var ok = false;
    switch (item.kind) {
      case SendQueueKind.text:
        ok = await _sendTextInternal(
          item.chatId,
          item.pathOrText,
          replyToMessageId: item.replyToMessageId,
          scheduleDate: item.scheduleDate,
          enqueueOnError: false,
        );
        break;
      case SendQueueKind.photo:
      case SendQueueKind.video:
      case SendQueueKind.audio:
      case SendQueueKind.document:
      case SendQueueKind.voice:
        await flushSendQueue();
        ok = !queue.items.any((i) => i.id == item.id);
        break;
    }
    if (ok) await queue.remove(item.id);
    return ok;
  }

  List<FocusMessage> failedMessagesFor(int chatId) {
    final queue = _sendQueue;
    if (queue == null) return const [];
    return queue.items
        .where((i) => i.chatId == chatId)
        .map(FocusMessage.fromQueueItem)
        .toList();
  }

  int? firstUnreadMessageId(int chatId) {
    final chat = _chats[chatId];
    final list = _messagesByChat[chatId];
    if (chat == null || list == null || list.isEmpty) return null;
    final marker = chat.lastReadInboxMessageId;
    for (final msg in list) {
      if (!msg.isOutgoing && msg.id > marker) return msg.id;
    }
    return null;
  }

  void _upsertMessage(FocusMessage message) {
    final list = _messagesByChat.putIfAbsent(message.chatId, () => []);
    final idx = list.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      list[idx] = message;
    } else {
      list.add(message);
      list.sort((a, b) => a.id.compareTo(b.id));
    }
  }

  void _handleMessageContentUpdate(Map<String, dynamic> map) {
    final chatId = FocusChat.asInt(map['chat_id']);
    final messageId = FocusChat.asInt(map['message_id']);
    final newContent = map['new_content'];
    if (chatId == 0 || messageId == 0) return;
    final list = _messagesByChat[chatId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final old = list[idx];
    final media = FocusMessage.parseMedia(newContent);
    list[idx] = FocusMessage(
      id: old.id,
      chatId: old.chatId,
      text: FocusChat.previewFromContent(newContent),
      date: old.date,
      isOutgoing: old.isOutgoing,
      senderUserId: old.senderUserId,
      senderChatId: old.senderChatId,
      senderName: old.senderName,
      replyToMessageId: old.replyToMessageId,
      replyPreview: old.replyPreview,
      mediaKind: media.kind,
      mediaFileId: media.fileId,
      fileName: media.fileName,
      durationSeconds: media.duration,
      mentionsMe: old.mentionsMe,
      containsUnreadMention: old.containsUnreadMention,
      canBeEdited: true,
      reactions: old.reactions,
    );
    notifyListeners();
  }

  void _handleMessageInteractionUpdate(Map<String, dynamic> map) {
    final chatId = FocusChat.asInt(map['chat_id']);
    final messageId = FocusChat.asInt(map['message_id']);
    final info = map['interaction_info'];
    if (chatId == 0 || messageId == 0 || info is! Map<String, dynamic>) return;
    final list = _messagesByChat[chatId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(
      reactions: FocusMessage.parseReactions(info),
    );
    notifyListeners();
  }

  void _handleDeleteMessagesUpdate(Map<String, dynamic> map) {
    final chatId = FocusChat.asInt(map['chat_id']);
    final ids = (map['message_ids'] as List? ?? const [])
        .map(FocusChat.asInt)
        .toList();
    if (chatId == 0 || ids.isEmpty) return;
    final list = _messagesByChat[chatId];
    if (list == null) return;
    list.removeWhere((m) => ids.contains(m.id));
    notifyListeners();
  }

  Future<void> logOut() async {
    _backgroundSyncTimer?.cancel();
    await _send(const td.LogOut());
    _chats.clear();
    _messagesByChat.clear();
    _userNames.clear();
    _chatsLoaded = false;
    _tdlibParametersSent = false;
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  FocusMessage? _findMessage(List<FocusMessage> list, int id) {
    for (final message in list) {
      if (message.id == id) return message;
    }
    return null;
  }

  Future<void> _tearDownReceiveLoop() async {
    await _receiveSub?.cancel();
    _receiveSub = null;
    _receivePort?.close();
    _receivePort = null;
    _receiveIsolate?.kill(priority: Isolate.immediate);
    _receiveIsolate = null;
  }

  /// Best-effort graceful shutdown so hot restart can reclaim the binlog.
  Future<void> shutdown() async {
    final id = _clientId;
    if (id != 0) {
      try {
        tdSend(id, const td.Close());
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await stopExistingTdlibReceiveIsolate();
    await _tearDownReceiveLoop();
    _clientId = 0;
    _tdlibParametersSent = false;
    await _clearPersistedClientIds();
  }

  @override
  void dispose() {
    _backgroundSyncTimer?.cancel();
    if (_clientId != 0) {
      try {
        tdSend(_clientId, const td.Close());
      } catch (_) {}
      unawaited(_persistActiveClientId(_clientId));
      _clientId = 0;
    }
    // Prefer cooperative stop so the next start() does not race td_receive.
    unawaited(stopExistingTdlibReceiveIsolate().then((_) => _tearDownReceiveLoop()));
    super.dispose();
  }
}

class FocusMessage {
  const FocusMessage({
    required this.id,
    required this.chatId,
    required this.text,
    required this.date,
    required this.isOutgoing,
    this.senderUserId,
    this.senderChatId,
    this.senderName,
    this.replyToMessageId,
    this.replyPreview,
    this.mediaKind = FocusMediaKind.none,
    this.mediaFileId,
    this.fileName,
    this.durationSeconds,
    this.mentionsMe = false,
    this.containsUnreadMention = false,
    this.canBeEdited = false,
    this.reactions = const {},
    this.entities = const [],
    this.isFailed = false,
    this.localId,
    this.queueItemId,
  });

  final int id;
  final int chatId;
  final String text;
  final int date;
  final bool isOutgoing;
  final int? senderUserId;
  final int? senderChatId;
  final String? senderName;
  final int? replyToMessageId;
  final String? replyPreview;
  final FocusMediaKind mediaKind;
  final int? mediaFileId;
  final String? fileName;
  final int? durationSeconds;
  final bool mentionsMe;
  final bool containsUnreadMention;
  final bool canBeEdited;
  final Map<String, int> reactions;
  final List<FocusTextEntity> entities;
  final bool isFailed;
  final String? localId;
  final String? queueItemId;

  bool get isPhoto => mediaKind == FocusMediaKind.photo;
  bool get isVideo => mediaKind == FocusMediaKind.video;
  bool get isAudio => mediaKind == FocusMediaKind.audio;
  bool get isFile => mediaKind == FocusMediaKind.file;
  bool get isAnimation => mediaKind == FocusMediaKind.animation;
  bool get isVoice => mediaKind == FocusMediaKind.voice;
  bool get isSticker => mediaKind == FocusMediaKind.sticker;
  bool get hasOpenableMedia => mediaFileId != null;
  bool get hasReactions => reactions.isNotEmpty;
  bool get isPending => isFailed || localId != null;

  /// Back-compat for older call sites.
  int? get photoFileId => isPhoto ? mediaFileId : null;

  FocusMessage copyWith({
    String? senderName,
    String? replyPreview,
    String? text,
    Map<String, int>? reactions,
    bool? canBeEdited,
    List<FocusTextEntity>? entities,
    bool? isFailed,
  }) {
    return FocusMessage(
      id: id,
      chatId: chatId,
      text: text ?? this.text,
      date: date,
      isOutgoing: isOutgoing,
      senderUserId: senderUserId,
      senderChatId: senderChatId,
      senderName: senderName ?? this.senderName,
      replyToMessageId: replyToMessageId,
      replyPreview: replyPreview ?? this.replyPreview,
      mediaKind: mediaKind,
      mediaFileId: mediaFileId,
      fileName: fileName,
      durationSeconds: durationSeconds,
      mentionsMe: mentionsMe,
      containsUnreadMention: containsUnreadMention,
      canBeEdited: canBeEdited ?? this.canBeEdited,
      reactions: reactions ?? this.reactions,
      entities: entities ?? this.entities,
      isFailed: isFailed ?? this.isFailed,
      localId: localId,
      queueItemId: queueItemId,
    );
  }

  static FocusMessage fromQueueItem(SendQueueItem item) {
    final preview = switch (item.kind) {
      SendQueueKind.text => item.pathOrText,
      SendQueueKind.photo => item.caption ?? '[photo]',
      SendQueueKind.video => item.caption ?? '[video]',
      SendQueueKind.audio => item.caption ?? '♫ Audio',
      SendQueueKind.document => item.pathOrText.split('/').last,
      SendQueueKind.voice => '[voice]',
    };
    final kind = switch (item.kind) {
      SendQueueKind.photo => FocusMediaKind.photo,
      SendQueueKind.video => FocusMediaKind.video,
      SendQueueKind.audio => FocusMediaKind.audio,
      SendQueueKind.document => FocusMediaKind.file,
      SendQueueKind.voice => FocusMediaKind.voice,
      SendQueueKind.text => FocusMediaKind.none,
    };
    return FocusMessage(
      id: -item.id.hashCode,
      chatId: item.chatId,
      text: preview,
      date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      isOutgoing: true,
      replyToMessageId: item.replyToMessageId,
      mediaKind: kind,
      isFailed: true,
      localId: item.id,
      queueItemId: item.id,
      durationSeconds: item.durationSeconds,
    );
  }

  static FocusMessage? fromTdJson(
    Map<String, dynamic> message, {
    int? myUserId,
  }) {
    try {
      final chatId = FocusChat.asInt(message['chat_id']);
      final id = FocusChat.asInt(message['id']);
      if (id == 0 || chatId == 0) return null;

      int? senderUserId;
      int? senderChatId;
      final sender = message['sender_id'];
      if (sender is Map<String, dynamic>) {
        switch (sender['@type']) {
          case 'messageSenderUser':
            senderUserId = FocusChat.asInt(sender['user_id']);
            break;
          case 'messageSenderChat':
            senderChatId = FocusChat.asInt(sender['chat_id']);
            break;
        }
      }

      int? replyToMessageId;
      final replyTo = message['reply_to'];
      if (replyTo is Map<String, dynamic> &&
          replyTo['@type'] == 'messageReplyToMessage') {
        replyToMessageId = FocusChat.asInt(replyTo['message_id']);
      }

      final content = message['content'];
      final media = parseMedia(content);
      final textData = _extractTextAndEntities(content);
      final canEdit = message['can_be_edited'] == true;
      final containsUnreadMention =
          message['contains_unread_mention'] == true;
      final mentionsMe = _messageMentionsUser(content, myUserId);
      final reactions = parseReactions(message['interaction_info']);

      return FocusMessage(
        id: id,
        chatId: chatId,
        text: textData.text.isNotEmpty
            ? textData.text
            : FocusChat.previewFromContent(content),
        date: FocusChat.asInt(message['date']),
        isOutgoing: message['is_outgoing'] == true,
        senderUserId: senderUserId,
        senderChatId: senderChatId,
        replyToMessageId: replyToMessageId,
        mediaKind: media.kind,
        mediaFileId: media.fileId,
        fileName: media.fileName,
        durationSeconds: media.duration,
        mentionsMe: mentionsMe,
        containsUnreadMention: containsUnreadMention,
        canBeEdited: canEdit,
        reactions: reactions,
        entities: textData.entities,
      );
    } catch (_) {
      return null;
    }
  }

  static ({String text, List<FocusTextEntity> entities}) _extractTextAndEntities(
    dynamic content,
  ) {
    if (content is! Map<String, dynamic>) {
      return (text: '', entities: const []);
    }
    Map<String, dynamic>? formatted;
    if (content['@type'] == 'messageText') {
      formatted = content['text'] as Map<String, dynamic>?;
    } else {
      final caption = content['caption'];
      if (caption is Map<String, dynamic>) formatted = caption;
    }
    if (formatted == null) return (text: '', entities: const []);
    final text = '${formatted['text'] ?? ''}';
    final entities = FocusTextEntity.fromTdJson(
      formatted['entities'] as List?,
    );
    return (text: text, entities: entities);
  }

  static bool _messageMentionsUser(dynamic content, int? myUserId) {
    if (myUserId == null || content is! Map<String, dynamic>) return false;
    if (content['@type'] != 'messageText') return false;
    final text = content['text'];
    if (text is! Map<String, dynamic>) return false;
    final entities = text['entities'] as List? ?? const [];
    for (final entity in entities) {
      if (entity is! Map<String, dynamic>) continue;
      final type = entity['type'];
      if (type is Map<String, dynamic> &&
          type['@type'] == 'textEntityTypeMentionName') {
        if (FocusChat.asInt(type['user_id']) == myUserId) return true;
      }
    }
    return false;
  }

  static Map<String, int> parseReactions(dynamic interactionInfo) {
    if (interactionInfo is! Map<String, dynamic>) return const {};
    final reactions = interactionInfo['reactions'];
    if (reactions is! Map<String, dynamic>) return const {};
    final list = reactions['reactions'] as List? ?? const [];
    final out = <String, int>{};
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final type = item['type'];
      if (type is! Map<String, dynamic>) continue;
      if (type['@type'] != 'reactionTypeEmoji') continue;
      final emoji = type['emoji'] as String?;
      if (emoji == null || emoji.isEmpty) continue;
      out[emoji] = FocusChat.asInt(item['total_count']);
    }
    return out;
  }

  static ({FocusMediaKind kind, int? fileId, String? fileName, int? duration})
      parseMedia(dynamic content) {
    if (content is! Map<String, dynamic>) {
      return (
        kind: FocusMediaKind.none,
        fileId: null,
        fileName: null,
        duration: null,
      );
    }
    switch (content['@type']) {
      case 'messagePhoto':
        return (
          kind: FocusMediaKind.photo,
          fileId: _largestPhotoFileId(content),
          fileName: null,
          duration: null,
        );
      case 'messageVideo':
        final video = content['video'];
        if (video is Map<String, dynamic>) {
          final file = video['video'];
          return (
            kind: FocusMediaKind.video,
            fileId: file is Map ? FocusChat.asInt(file['id']) : null,
            fileName: video['file_name'] as String?,
            duration: FocusChat.asInt(video['duration']),
          );
        }
        break;
      case 'messageAudio':
        final audio = content['audio'];
        if (audio is Map<String, dynamic>) {
          final file = audio['audio'];
          final title = '${audio['title'] ?? ''}'.trim();
          final performer = '${audio['performer'] ?? ''}'.trim();
          final name = [
            if (performer.isNotEmpty) performer,
            if (title.isNotEmpty) title,
          ].join(' — ');
          return (
            kind: FocusMediaKind.audio,
            fileId: file is Map ? FocusChat.asInt(file['id']) : null,
            fileName: name.isNotEmpty
                ? name
                : (audio['file_name'] as String? ?? 'Audio'),
            duration: FocusChat.asInt(audio['duration']),
          );
        }
        break;
      case 'messageDocument':
        final doc = content['document'];
        if (doc is Map<String, dynamic>) {
          final file = doc['document'];
          return (
            kind: FocusMediaKind.file,
            fileId: file is Map ? FocusChat.asInt(file['id']) : null,
            fileName: doc['file_name'] as String? ?? 'File',
            duration: null,
          );
        }
        break;
      case 'messageVoiceNote':
        final voice = content['voice_note'];
        if (voice is Map<String, dynamic>) {
          final file = voice['voice'];
          return (
            kind: FocusMediaKind.voice,
            fileId: file is Map ? FocusChat.asInt(file['id']) : null,
            fileName: 'Voice message',
            duration: FocusChat.asInt(voice['duration']),
          );
        }
        break;
      case 'messageAnimation':
        final animation = content['animation'];
        if (animation is Map<String, dynamic>) {
          final file = animation['animation'];
          return (
            kind: FocusMediaKind.animation,
            fileId: file is Map ? FocusChat.asInt(file['id']) : null,
            fileName: animation['file_name'] as String? ?? 'GIF',
            duration: FocusChat.asInt(animation['duration']),
          );
        }
        break;
      case 'messageSticker':
        final sticker = content['sticker'];
        if (sticker is Map<String, dynamic>) {
          final file = sticker['sticker'];
          final emoji = '${sticker['emoji'] ?? ''}';
          return (
            kind: FocusMediaKind.sticker,
            fileId: file is Map ? FocusChat.asInt(file['id']) : null,
            fileName: emoji.isNotEmpty ? emoji : 'Sticker',
            duration: null,
          );
        }
        break;
    }
    return (
      kind: FocusMediaKind.none,
      fileId: null,
      fileName: null,
      duration: null,
    );
  }

  static int? _largestPhotoFileId(dynamic content) {
    if (content is! Map<String, dynamic>) return null;
    if (content['@type'] != 'messagePhoto') return null;
    final photo = content['photo'];
    if (photo is! Map<String, dynamic>) return null;
    final sizes = photo['sizes'];
    if (sizes is! List || sizes.isEmpty) return null;

    Map<String, dynamic>? best;
    var bestArea = -1;
    for (final size in sizes) {
      if (size is! Map<String, dynamic>) continue;
      final w = FocusChat.asInt(size['width']);
      final h = FocusChat.asInt(size['height']);
      final area = w * h;
      if (area >= bestArea) {
        bestArea = area;
        best = size;
      }
    }
    final file = best?['photo'];
    if (file is! Map<String, dynamic>) return null;
    final id = FocusChat.asInt(file['id']);
    return id == 0 ? null : id;
  }
}

enum FocusMediaKind { none, photo, video, audio, file, animation, voice, sticker }
