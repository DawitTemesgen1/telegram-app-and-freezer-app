import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:video_compress/video_compress.dart';

import '../../data/chat_prefs_store.dart';
import '../../data/drafts_store.dart';
import '../../data/followed_chats_store.dart';
import '../../data/send_queue_store.dart';
import '../../tdlib/focus_chat.dart';
import '../../tdlib/telegram_client.dart';
import '../../utils/app_snack.dart';
import '../../utils/chat_export.dart';
import '../../utils/media_helpers.dart';
import '../../utils/message_utils.dart';
import '../../utils/text_entities.dart';
import '../widgets/audio_player_sheet.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_info_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/pinned_messages_bar.dart';
import '../widgets/sticker_picker.dart';
import '../widgets/voice_waveform.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final int chatId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ListEntry {
  _ListEntry.message(this.message)
      : kind = _EntryKind.message,
        dateLabel = null,
        firstUnread = false;

  _ListEntry.dateSeparator(this.dateLabel)
      : kind = _EntryKind.dateSeparator,
        message = null,
        firstUnread = false;

  _ListEntry.unreadDivider()
      : kind = _EntryKind.unreadDivider,
        message = null,
        dateLabel = null,
        firstUnread = false;

  final _EntryKind kind;
  final FocusMessage? message;
  final String? dateLabel;
  final bool firstUnread;
}

enum _EntryKind { message, dateSeparator, unreadDivider }

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _searchController = TextEditingController();
  final _recorder = AudioRecorder();
  final _focusNode = FocusNode();

  late final TelegramClient _client;
  late final DraftsStore _drafts;
  late final ChatPrefsStore _chatPrefs;

  bool _sending = false;
  bool _loadingOlder = false;
  bool _searchOpen = false;
  bool _searching = false;
  bool _showEmojiPicker = false;
  bool _showScrollFab = false;
  bool _nearBottom = true;
  bool _didInitialAnchor = false;
  bool _anchorScheduled = false;
  int _anchorRetries = 0;
  bool _selectionMode = false;
  bool _recordingVoice = false;
  bool _pinnedBarHidden = false;
  int _recordingSeconds = 0;
  Timer? _recordTimer;
  DateTime? _lastTypingSent;
  FocusMessage? _replyTo;
  List<FocusMessage> _searchResults = const [];
  final Set<int> _selectedIds = {};
  List<({int userId, String name, String? username})> _mentionCandidates =
      const [];
  String _mentionQuery = '';
  Timer? _mentionDebounce;
  final Map<int, String> _inlineMediaPaths = {};
  int? _highlightMessageId;
  int _lastEntryCount = 0;

  @override
  void initState() {
    super.initState();
    _client = context.read<TelegramClient>();
    _drafts = context.read<DraftsStore>();
    _chatPrefs = context.read<ChatPrefsStore>();
    _controller.text = _drafts.draftFor(widget.chatId);
    _controller.addListener(_onDraftChanged);
    _itemPositionsListener.itemPositions.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _client.openChat(widget.chatId);
      await _client.loadChatHistory(widget.chatId);
      await _client.loadPinnedMessage(widget.chatId);
      if (mounted) _scheduleInitialAnchor();
    });
  }

  @override
  void dispose() {
    _mentionDebounce?.cancel();
    _recordTimer?.cancel();
    _controller.removeListener(_onDraftChanged);
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    _client.closeChat(widget.chatId);
    _controller.dispose();
    _searchController.dispose();
    _recorder.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<FocusMessage> _allMessages() {
    final base = _client.messagesFor(widget.chatId);
    final failed = _client.failedMessagesFor(widget.chatId);
    return [...base, ...failed];
  }

  List<_ListEntry> _buildEntries(List<FocusMessage> messages, FocusChat? chat) {
    if (messages.isEmpty) return const [];
    final sorted = List<FocusMessage>.from(messages)
      ..sort((a, b) => a.id.compareTo(b.id));
    final firstUnreadId = chat == null
        ? null
        : _client.firstUnreadMessageId(widget.chatId);
    var unreadDividerInserted = firstUnreadId == null;
    final entries = <_ListEntry>[];
    for (var i = 0; i < sorted.length; i++) {
      final msg = sorted[i];
      if (i == 0 ||
          !isSameDay(sorted[i - 1].date, msg.date)) {
        entries.add(_ListEntry.dateSeparator(formatDateSeparator(msg.date)));
      }
      if (!unreadDividerInserted &&
          firstUnreadId != null &&
          msg.id == firstUnreadId) {
        entries.add(_ListEntry.unreadDivider());
        unreadDividerInserted = true;
      }
      entries.add(_ListEntry.message(msg));
    }
    return entries;
  }

  int? _indexForMessageId(List<_ListEntry> entries, int messageId) {
    for (var i = 0; i < entries.length; i++) {
      final m = entries[i].message;
      if (m != null && m.id == messageId) return i;
    }
    return null;
  }

  int _listIndexForEntry(int entryIndex) =>
      entryIndex + (_loadingOlder ? 1 : 0);

  int _lastListIndex(int entryCount) {
    if (entryCount <= 0) return 0;
    return _listIndexForEntry(entryCount - 1);
  }

  void _scrollToMessageId(int messageId, {bool highlight = false}) {
    final entries = _buildEntries(_allMessages(), _client.chatById(widget.chatId));
    final index = _indexForMessageId(entries, messageId);
    if (index == null || !_itemScrollController.isAttached) return;
    _itemScrollController.scrollTo(
      index: _listIndexForEntry(index),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.35,
    );
    if (highlight) {
      setState(() => _highlightMessageId = messageId);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightMessageId = null);
      });
    }
  }

  void _scheduleInitialAnchor() {
    if (_didInitialAnchor || _anchorScheduled) return;
    _anchorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorScheduled = false;
      if (!mounted || _didInitialAnchor) return;
      final entries =
          _buildEntries(_allMessages(), _client.chatById(widget.chatId));
      if (entries.isEmpty || !_itemScrollController.isAttached) {
        if (_anchorRetries++ < 40) _scheduleInitialAnchor();
        return;
      }
      _didInitialAnchor = true;
      final firstUnread = _client.firstUnreadMessageId(widget.chatId);
      if (firstUnread != null) {
        _scrollToMessageId(firstUnread, highlight: true);
      } else {
        _scrollToBottom(instant: true);
      }
    });
  }

  void _onDraftChanged() {
    _drafts.setDraft(widget.chatId, _controller.text);
    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!) > const Duration(seconds: 4)) {
      _lastTypingSent = now;
      unawaited(_client.sendTyping(widget.chatId));
    }
    _updateMentionOverlay();
  }

  void _updateMentionOverlay() {
    final text = _controller.text;
    final sel = _controller.selection.baseOffset;
    if (sel < 0) {
      if (_mentionCandidates.isNotEmpty) {
        setState(() => _mentionCandidates = const []);
      }
      return;
    }
    final before = text.substring(0, sel);
    final at = before.lastIndexOf('@');
    if (at < 0) {
      if (_mentionCandidates.isNotEmpty) {
        setState(() => _mentionCandidates = const []);
      }
      return;
    }
    final query = before.substring(at + 1);
    if (query.contains(' ') || query.contains('\n')) {
      if (_mentionCandidates.isNotEmpty) {
        setState(() => _mentionCandidates = const []);
      }
      return;
    }
    if (query == _mentionQuery && _mentionCandidates.isNotEmpty) return;
    _mentionQuery = query;
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (query.isEmpty) {
        if (mounted) setState(() => _mentionCandidates = const []);
        return;
      }
      final results =
          await _client.searchChatMembers(widget.chatId, query, limit: 8);
      if (mounted) setState(() => _mentionCandidates = results);
    });
  }

  void _insertMention(({int userId, String name, String? username}) member) {
    final text = _controller.text;
    final sel = _controller.selection.baseOffset;
    final before = text.substring(0, sel);
    final at = before.lastIndexOf('@');
    if (at < 0) return;
    final username = member.username ?? member.name.replaceAll(' ', '');
    final mention = '@$username ';
    final updated = '${text.substring(0, at)}$mention${text.substring(sel)}';
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: at + mention.length),
    );
    setState(() => _mentionCandidates = const []);
  }

  void _onScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final minIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a < b ? a : b);
    final maxIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a > b ? a : b);
    final entries =
        _buildEntries(_allMessages(), _client.chatById(widget.chatId));
    if (entries.isEmpty) return;

    final lastIndex = _lastListIndex(entries.length);
    // Chronological list: newest at the end. FAB when not near the bottom.
    final nearBottom = maxIndex >= lastIndex - 1;
    final showFab = !nearBottom;
    if ((showFab != _showScrollFab || nearBottom != _nearBottom) && mounted) {
      setState(() {
        _showScrollFab = showFab;
        _nearBottom = nearBottom;
      });
    } else {
      _nearBottom = nearBottom;
    }

    // Load history when scrolled near the oldest messages (top).
    final topThreshold = _loadingOlder ? 2 : 1;
    if (minIndex <= topThreshold) {
      _loadOlder();
    }
  }

  void _scrollToBottom({bool instant = false}) {
    final entries =
        _buildEntries(_allMessages(), _client.chatById(widget.chatId));
    if (entries.isEmpty || !_itemScrollController.isAttached) return;
    final index = _lastListIndex(entries.length);
    if (instant) {
      _itemScrollController.jumpTo(index: index, alignment: 1.0);
    } else {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        alignment: 1.0,
      );
    }
    if (mounted) {
      setState(() {
        _showScrollFab = false;
        _nearBottom = true;
      });
    }
  }

  void _followNewMessagesIfNeeded(int entryCount) {
    if (!_didInitialAnchor || !_nearBottom) {
      _lastEntryCount = entryCount;
      return;
    }
    if (entryCount > _lastEntryCount && _lastEntryCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom(instant: true);
      });
    }
    _lastEntryCount = entryCount;
  }

  void _jumpToFirstUnread() {
    final id = _client.firstUnreadMessageId(widget.chatId);
    if (id != null) _scrollToMessageId(id, highlight: true);
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_client.hasMoreHistory(widget.chatId)) return;
    setState(() => _loadingOlder = true);
    await _client.loadOlderMessages(widget.chatId);
    if (mounted) setState(() => _loadingOlder = false);
  }

  Future<int?> _pickScheduleDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return null;
    final scheduled =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) return null;
    return scheduled.millisecondsSinceEpoch ~/ 1000;
  }

  Future<void> _send({int? scheduleDate}) async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final replyId = _replyTo?.id;
    setState(() {
      _sending = true;
      _replyTo = null;
      _showEmojiPicker = false;
    });
    _controller.clear();
    await _drafts.clearDraft(widget.chatId);
    try {
      await _client.sendText(
        widget.chatId,
        text,
        replyToMessageId: replyId,
        scheduleDate: scheduleDate,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setReply(FocusMessage message) {
    if (_selectionMode) return;
    setState(() => _replyTo = message);
  }

  void _enterSelection(FocusMessage message) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(message.id);
    });
  }

  void _toggleSelection(int messageId) {
    setState(() {
      if (_selectedIds.contains(messageId)) {
        _selectedIds.remove(messageId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(messageId);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  List<FocusMessage> _selectedMessages(List<FocusMessage> all) =>
      all.where((m) => _selectedIds.contains(m.id)).toList();

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);
    final results = await _client.searchChatMessages(widget.chatId, query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  Future<void> _jumpToSearchHit(FocusMessage hit) async {
    var messages = _allMessages();
    if (!messages.any((m) => m.id == hit.id)) {
      await _client.loadChatHistory(
        widget.chatId,
        fromMessageId: hit.id,
        markRead: false,
      );
      messages = _allMessages();
    }
    if (!mounted) return;
    setState(() {
      _searchOpen = false;
      _searchResults = const [];
      _searchController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMessageId(hit.id, highlight: true);
    });
  }

  Future<String?> _promptCaption() async {
    final ctrl = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Caption'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Optional caption'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    return caption;
  }

  Future<void> _ensureInlineMedia(FocusMessage message) async {
    final fileId = message.mediaFileId;
    if (fileId == null) return;
    if (_inlineMediaPaths.containsKey(message.id)) return;
    final path = await _client.downloadFile(fileId);
    if (path != null && mounted) {
      setState(() => _inlineMediaPaths[message.id] = path);
    }
  }

  Future<void> _openMedia(FocusMessage message, List<FocusMessage> all) async {
    final fileId = message.mediaFileId;
    if (fileId == null) return;

    if (message.isPhoto) {
      final photos = all.where((m) => m.isPhoto && m.mediaFileId != null).toList();
      final index = photos.indexWhere((m) => m.id == message.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoGalleryViewer(
            messages: photos,
            initialIndex: index < 0 ? 0 : index,
          ),
        ),
      );
      return;
    }

    if (message.isVideo || message.isAnimation) {
      await _ensureInlineMedia(message);
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    final path = await _client.downloadFile(fileId);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (path == null || path.isEmpty) {
      showAppSnack(context, 'Could not download file', error: true);
      return;
    }

    if (message.isAudio || message.isVoice) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => AudioPlayerSheet(
          path: path,
          title: message.fileName ?? 'Audio',
        ),
      );
      return;
    }

    if (isPdfFileName(message.fileName)) {
      await OpenFilex.open(path);
      return;
    }

    await OpenFilex.open(path);
  }

  Future<void> _retryFailed(FocusMessage message) async {
    final queue = context.read<SendQueueStore>();
    final item = queue.items
        .cast<SendQueueItem?>()
        .firstWhere(
          (i) => i?.id == message.queueItemId,
          orElse: () => null,
        );
    if (item == null) return;
    setState(() => _sending = true);
    try {
      final ok = await _client.retryQueueItem(item);
      if (mounted && !ok) {
        showAppSnack(context, 'Retry failed', error: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _saveMedia(FocusMessage message) async {
    final fileId = message.mediaFileId;
    if (fileId == null) return;
    final path = await _client.downloadFile(fileId);
    if (path == null || !mounted) return;
    final saved = await saveMediaToDownloads(path, fileName: message.fileName);
    if (!mounted) return;
    showAppSnack(
      context,
      saved == null ? 'Save failed' : 'Saved',
      error: saved == null,
    );
  }

  Future<void> _pickAndSend(FileType type) async {
    final file = await FilePicker.pickFile(type: type);
    if (file == null) return;
    var path = file.path;
    if (path == null || path.isEmpty) return;

    final caption = await _promptCaption();
    if (!mounted || caption == null) return;
    final scheduleDate = await _pickScheduleDate();
    if (!mounted) return;

    final replyId = _replyTo?.id;
    setState(() {
      _sending = true;
      _replyTo = null;
    });
    try {
      if (type == FileType.video) {
        final info = await VideoCompress.compressVideo(
          path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
        );
        if (info?.path != null) path = info!.path!;
      }
      switch (type) {
        case FileType.image:
          await _client.sendPhotoFile(
            widget.chatId,
            path,
            replyToMessageId: replyId,
            caption: caption.isEmpty ? null : caption,
            scheduleDate: scheduleDate,
          );
          break;
        case FileType.video:
          await _client.sendVideoFile(
            widget.chatId,
            path,
            replyToMessageId: replyId,
            caption: caption.isEmpty ? null : caption,
            scheduleDate: scheduleDate,
          );
          break;
        case FileType.audio:
          await _client.sendAudioFile(
            widget.chatId,
            path,
            replyToMessageId: replyId,
            caption: caption.isEmpty ? null : caption,
            scheduleDate: scheduleDate,
          );
          break;
        default:
          await _client.sendDocumentFile(
            widget.chatId,
            path,
            replyToMessageId: replyId,
            caption: caption.isEmpty ? null : caption,
            scheduleDate: scheduleDate,
          );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleVoiceRecord() async {
    if (_recordingVoice) {
      _recordTimer?.cancel();
      final path = await _recorder.stop();
      final duration = _recordingSeconds;
      setState(() {
        _recordingVoice = false;
        _recordingSeconds = 0;
      });
      if (path == null || path.isEmpty) return;
      final replyId = _replyTo?.id;
      setState(() {
        _sending = true;
        _replyTo = null;
      });
      try {
        await _client.sendVoiceNote(
          widget.chatId,
          path,
          durationSeconds: duration.clamp(1, 3600),
          replyToMessageId: replyId,
        );
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        showAppSnack(context, 'Microphone permission required', error: true);
      }
      return;
    }
    final dir = Directory.systemTemp;
    final file =
        p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    await _recorder.start(const RecordConfig(), path: file);
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingSeconds += 1);
    });
    setState(() => _recordingVoice = true);
  }

  void _applyFormat(String wrapper) {
    final text = _controller.text;
    final sel = _controller.selection;
    final updated = wrapSelection(text, sel, wrapper);
    final delta = wrapper.length * 2;
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: (sel.start + delta).clamp(0, updated.length),
      ),
    );
  }

  Future<void> _showMessageActions(FocusMessage message) async {
    if (_selectionMode) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.reply_outlined),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(context);
                    _setReply(message);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_selectionActionCopy([message]));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.forward_outlined),
                  title: const Text('Forward'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_selectionActionForward([message]));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined),
                  title: const Text('React'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_selectionActionReact([message]));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: const Text('Pin'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_selectionActionPin([message]));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.more_horiz),
                  title: const Text('More…'),
                  onTap: () {
                    Navigator.pop(context);
                    _showMessageMoreActions(message);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMessageMoreActions(FocusMessage message) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isOutgoing && message.canBeEdited)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _editMessage(message);
                  },
                ),
              if (message.hasOpenableMedia)
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Save media'),
                  onTap: () {
                    Navigator.pop(context);
                    _saveMedia(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Copy link'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_selectionActionLink([message]));
                },
              ),
              ListTile(
                leading: const Icon(Icons.checklist),
                title: const Text('Select'),
                onTap: () {
                  Navigator.pop(context);
                  _enterSelection(message);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_selectionActionDelete([message]));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editMessage(FocusMessage message) async {
    final ctrl = TextEditingController(text: message.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _client.editText(widget.chatId, message.id, ctrl.text);
  }

  Future<void> _selectionActionCopy(List<FocusMessage> selected) async {
    final text = selected.map((m) => m.text).join('\n');
    await copyToClipboard(text);
    _exitSelection();
    if (mounted) {
      showAppSnack(context, 'Copied');
    }
  }

  Future<void> _selectionActionLink(List<FocusMessage> selected) async {
    if (selected.length != 1) return;
    final link = await _client.getMessageLink(widget.chatId, selected.first.id);
    if (link == null || !mounted) return;
    await copyToClipboard(link);
    _exitSelection();
    if (!mounted) return;
    showAppSnack(context, 'Link copied');
  }

  Future<void> _selectionActionDelete(List<FocusMessage> selected) async {
    final revoke = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete messages?'),
        content: Text(
          'Delete ${selected.length} message(s)? '
          'This cannot be undone on Telegram servers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Delete for me'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete for everyone'),
          ),
        ],
      ),
    );
    if (revoke == null) return;

    final ids = selected.map((m) => m.id).where((id) => id > 0).toList();
    if (ids.isEmpty) {
      _exitSelection();
      return;
    }

    await _client.deleteMessages(widget.chatId, ids, revoke: revoke);
    _exitSelection();

    if (!mounted) return;
    showAppSnack(
      context,
      'Deleted ${ids.length} message(s)',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          showAppSnack(
            context,
            'Undo unavailable after server delete',
            error: true,
          );
        },
      ),
    );
  }

  Future<void> _selectionActionPin(List<FocusMessage> selected) async {
    for (final msg in selected) {
      await _chatPrefs.toggleLocalPin(widget.chatId, msg.id);
    }
    _exitSelection();
  }

  Future<void> _selectionActionReact(List<FocusMessage> selected) async {
    if (selected.length != 1) return;
    const emojis = ['👍', '❤️', '🔥', '😂', '😮', '😢'];
    final emoji = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('React'),
        children: emojis
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, e),
                child: Text(e, style: const TextStyle(fontSize: 28)),
              ),
            )
            .toList(),
      ),
    );
    if (emoji == null) return;
    await _client.addReaction(widget.chatId, selected.first.id, emoji);
    _exitSelection();
  }

  Future<void> _selectionActionForward(List<FocusMessage> selected) async {
    final followed = context.read<FollowedChatsStore>();
    final chats = _client.followedChats(followed.ids);
    final target = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: chats
                .where((c) => c.id != widget.chatId)
                .map(
                  (c) => ListTile(
                    title: Text(c.title),
                    onTap: () => Navigator.pop(context, c.id),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
    if (target == null) return;
    await _client.forwardMessages(
      widget.chatId,
      target,
      selected.map((m) => m.id).toList(),
    );
    _exitSelection();
  }

  void _showAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('Photo'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSend(FileType.image);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('Video'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSend(FileType.video);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.audiotrack_outlined),
                  title: const Text('Music / audio'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSend(FileType.audio);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: const Text('File'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSend(FileType.any);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.emoji_emotions_outlined),
                  title: const Text('Stickers'),
                  onTap: () {
                    Navigator.pop(context);
                    _showStickerPicker();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mood_outlined),
                  title: const Text('Emoji'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _showEmojiPicker = true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_send_outlined),
                  title: const Text('Schedule send'),
                  onTap: () async {
                    Navigator.pop(context);
                    if (_sending) return;
                    final date = await _pickScheduleDate();
                    if (date != null) await _send(scheduleDate: date);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Format',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.format_bold),
                  title: const Text('Bold'),
                  onTap: () {
                    Navigator.pop(context);
                    _applyFormat('**');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.format_italic),
                  title: const Text('Italic'),
                  onTap: () {
                    Navigator.pop(context);
                    _applyFormat('*');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('Code'),
                  onTap: () {
                    Navigator.pop(context);
                    _applyFormat('`');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Spoiler'),
                  onTap: () {
                    Navigator.pop(context);
                    _applyFormat('||');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _searchResults = const [];
      }
    });
  }

  void _showStickerPicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StickerPickerSheet(
        chatId: widget.chatId,
        onEmojiSticker: (emoji) => _client.sendText(widget.chatId, emoji),
      ),
    );
  }

  void _showChatInfo() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChatInfoSheet(
        chatId: widget.chatId,
        onExport: _exportChat,
      ),
    );
  }

  Future<void> _exportChat() async {
    final chat = _client.chatById(widget.chatId);
    if (chat == null) return;
    final messages = _client.messagesFor(widget.chatId);
    final path = await exportChatTranscript(
      chat: chat,
      messages: messages,
      senderName: _client.senderDisplayName,
    );
    if (!mounted) return;
    showAppSnack(
      context,
      path == null ? 'Export failed' : 'Exported',
      error: path == null,
    );
  }

  List<FocusMessage> _pinnedMessages(
    List<FocusMessage> messages,
    ChatPrefsStore chatPrefs,
  ) {
    final pins = <FocusMessage>[];
    final remote = _client.pinnedMessageFor(widget.chatId);
    if (remote != null) pins.add(remote);
    for (final id in chatPrefs.localPinnedIds(widget.chatId)) {
      final local = messages.cast<FocusMessage?>().firstWhere(
            (m) => m?.id == id,
            orElse: () => null,
          );
      if (local != null && !pins.any((p) => p.id == local.id)) {
        pins.add(local);
      }
    }
    return pins;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyK) {
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_selectionMode) {
        _exitSelection();
        return KeyEventResult.handled;
      }
      if (_searchOpen) {
        setState(() {
          _searchOpen = false;
          _searchResults = const [];
          _searchController.clear();
        });
        return KeyEventResult.handled;
      }
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.enter) {
      if (_controller.text.trim().isNotEmpty) {
        _send();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<TelegramClient>();
    final chatPrefs = context.watch<ChatPrefsStore>();
    final sendQueue = context.watch<SendQueueStore>();
    final chat = client.chatById(widget.chatId);
    final messages = _allMessages();
    final entries = _buildEntries(messages, chat);
    final theme = Theme.of(context);
    final loading = client.isLoadingHistory(widget.chatId) && messages.isEmpty;
    final showSenderNames = chat?.kind == 'group' || chat?.kind == 'channel';
    final subtitle = client.presenceSubtitle(widget.chatId);
    final selected = _selectedMessages(messages);
    final pinned = _pinnedBarHidden ? const <FocusMessage>[] : _pinnedMessages(messages, chatPrefs);
    final hasUnread = client.firstUnreadMessageId(widget.chatId) != null;

    if (!_didInitialAnchor && entries.isNotEmpty) {
      _scheduleInitialAnchor();
    }
    _followNewMessagesIfNeeded(entries.length);

    return Focus(
      onKeyEvent: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          leading: _selectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelection,
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
          title: _selectionMode
              ? Text('${selected.length} selected')
              : _searchOpen
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search in chat',
                        border: InputBorder.none,
                        filled: false,
                      ),
                      onSubmitted: _runSearch,
                      onChanged: (value) {
                        if (value.trim().length >= 2) {
                          _runSearch(value);
                        } else if (value.isEmpty) {
                          setState(() => _searchResults = const []);
                        }
                      },
                    )
                  : InkWell(
                      onTap: _showChatInfo,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            if (chat != null) ...[
                              ChatAvatar(
                                chat: chat,
                                imagePath: client.chatPhotoPath(widget.chatId),
                                size: 36,
                                showKindBadge: false,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chat?.title ?? 'Chat',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (subtitle.isNotEmpty)
                                    Text(
                                      subtitle,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: client.typingLabel(
                                                  widget.chatId) !=
                                              null
                                            ? theme.colorScheme.primary
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
          actions: [
            if (_selectionMode)
              PopupMenuButton<String>(
                tooltip: 'Actions',
                enabled: selected.isNotEmpty,
                onSelected: (value) {
                  switch (value) {
                    case 'copy':
                      _selectionActionCopy(selected);
                    case 'link':
                      _selectionActionLink(selected);
                    case 'forward':
                      _selectionActionForward(selected);
                    case 'pin':
                      _selectionActionPin(selected);
                    case 'react':
                      _selectionActionReact(selected);
                    case 'delete':
                      _selectionActionDelete(selected);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'copy', child: Text('Copy')),
                  PopupMenuItem(
                    value: 'link',
                    enabled: selected.length == 1,
                    child: const Text('Copy link'),
                  ),
                  const PopupMenuItem(
                    value: 'forward',
                    child: Text('Forward'),
                  ),
                  const PopupMenuItem(value: 'pin', child: Text('Pin')),
                  PopupMenuItem(
                    value: 'react',
                    enabled: selected.length == 1,
                    child: const Text('React'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              )
            else
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  switch (value) {
                    case 'search':
                      _toggleSearch();
                    case 'unread':
                      _jumpToFirstUnread();
                    case 'info':
                      _showChatInfo();
                    case 'export':
                      unawaited(_exportChat());
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'search',
                    child: Text(_searchOpen ? 'Close search' : 'Search'),
                  ),
                  if (hasUnread)
                    const PopupMenuItem(
                      value: 'unread',
                      child: Text('Jump to unread'),
                    ),
                  const PopupMenuItem(
                    value: 'info',
                    child: Text('Chat info'),
                  ),
                  const PopupMenuItem(
                    value: 'export',
                    child: Text('Export chat'),
                  ),
                ],
              ),
          ],
        ),
        body: Column(
          children: [
            if (pinned.isNotEmpty)
              PinnedMessagesBar(
                pinnedMessages: pinned,
                onTap: (m) => _scrollToMessageId(m.id, highlight: true),
                onClose: () => setState(() => _pinnedBarHidden = true),
              ),
            if (_searchOpen) ...[
              if (_searching) const LinearProgressIndicator(minHeight: 2),
              if (_searchResults.isNotEmpty)
                SizedBox(
                  height: 140,
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final hit = _searchResults[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          hit.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(formatMessageTime(hit.date)),
                        onTap: () => _jumpToSearchHit(hit),
                      );
                    },
                  ),
                ),
            ],
            Expanded(
              child: loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Loading messages…',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : entries.isEmpty
                      ? Center(
                          child: Text(
                            'No messages yet',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Stack(
                          children: [
                            ScrollablePositionedList.builder(
                              itemScrollController: _itemScrollController,
                              itemPositionsListener: _itemPositionsListener,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              itemCount:
                                  entries.length + (_loadingOlder ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (_loadingOlder && index == 0) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final entryIndex =
                                    _loadingOlder ? index - 1 : index;
                                final entry = entries[entryIndex];
                                if (entry.kind == _EntryKind.dateSeparator) {
                                  return _DateSeparator(label: entry.dateLabel!);
                                }
                                if (entry.kind == _EntryKind.unreadDivider) {
                                  return _UnreadDivider();
                                }
                                final message = entry.message!;
                                final fileId = message.mediaFileId;
                                final progress = fileId == null
                                    ? null
                                    : client.fileDownloadProgress(fileId);
                                return MessageBubble(
                                  message: message,
                                  senderName: client.senderDisplayName(message),
                                  showSenderName: showSenderNames,
                                  selected: _selectedIds.contains(message.id) ||
                                      _highlightMessageId == message.id,
                                  selectionMode: _selectionMode,
                                  onSelectToggle: () =>
                                      _toggleSelection(message.id),
                                  locallyPinned: chatPrefs.isLocallyPinned(
                                    widget.chatId,
                                    message.id,
                                  ),
                                  downloadProgress: progress,
                                  inlineVideoPath: message.isVideo
                                      ? _inlineMediaPaths[message.id]
                                      : null,
                                  inlineAnimationPath: message.isAnimation
                                      ? _inlineMediaPaths[message.id]
                                      : null,
                                  onLongPress: () =>
                                      _showMessageActions(message),
                                  onTap: message.hasOpenableMedia
                                      ? () => _openMedia(message, messages)
                                      : null,
                                  onReplyTap: message.replyToMessageId == null
                                      ? null
                                      : () {
                                          final rid = message.replyToMessageId!;
                                          _scrollToMessageId(rid, highlight: true);
                                        },
                                  onRetry: message.isFailed
                                      ? () => _retryFailed(message)
                                      : null,
                                  onMentionTap: (userId) {
                                    showAppSnack(
                                      context,
                                      client.userName(userId) ??
                                          'User $userId',
                                    );
                                  },
                                );
                              },
                            ),
                            if (_mentionCandidates.isNotEmpty)
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxHeight: 180),
                                    child: ListView(
                                      shrinkWrap: true,
                                      children: _mentionCandidates
                                          .map(
                                            (m) => ListTile(
                                              dense: true,
                                              title: Text(m.name),
                                              subtitle: m.username != null
                                                  ? Text('@${m.username}')
                                                  : null,
                                              onTap: () => _insertMention(m),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ),
                            if (_showScrollFab && !_selectionMode)
                              Positioned(
                                right: 16,
                                bottom: 20,
                                child: Material(
                                  elevation: 4,
                                  shape: const CircleBorder(),
                                  color: theme.colorScheme.primary,
                                  child: IconButton(
                                    tooltip: 'Scroll to bottom',
                                    onPressed: () => _scrollToBottom(),
                                    icon: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
            if (_replyTo != null && !_selectionMode)
              Material(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 36,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reply',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _replyTo!.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        onPressed: () => setState(() => _replyTo = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            if (_recordingVoice && !_selectionMode)
              Material(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.mic, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: VoiceWaveform(
                          active: true,
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatVoiceDuration(Duration(seconds: _recordingSeconds)),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_selectionMode) ...[
              if (_showEmojiPicker)
                SizedBox(
                  height: 260,
                  child: EmojiPicker(
                    onEmojiSelected: (_, emoji) {
                      _controller.text += emoji.emoji;
                    },
                    config: Config(
                      height: 256,
                      checkPlatformCompatibility: true,
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'More',
                        onPressed: _sending ? null : _showAttachSheet,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (_controller.text.trim().isNotEmpty) {
                              _send();
                            }
                          },
                          decoration: InputDecoration(
                            hintText: _recordingVoice
                                ? 'Recording… tap stop to send'
                                : 'Message',
                            suffixIcon: _showEmojiPicker
                                ? IconButton(
                                    tooltip: 'Keyboard',
                                    onPressed: () => setState(
                                      () => _showEmojiPicker = false,
                                    ),
                                    icon: const Icon(Icons.keyboard_outlined),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      ListenableBuilder(
                        listenable: _controller,
                        builder: (context, _) {
                          final hasText = _controller.text.trim().isNotEmpty;
                          if (_recordingVoice) {
                            return IconButton.filled(
                              tooltip: 'Stop & send',
                              onPressed: _sending ? null : _toggleVoiceRecord,
                              style: IconButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                                foregroundColor: theme.colorScheme.onError,
                              ),
                              icon: const Icon(Icons.stop),
                            );
                          }
                          if (hasText) {
                            return IconButton.filled(
                              onPressed: _sending ? null : () => _send(),
                              icon: _sending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                            );
                          }
                          return IconButton.filled(
                            tooltip: 'Voice note',
                            onPressed: _sending ? null : _toggleVoiceRecord,
                            icon: const Icon(Icons.mic_none),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (sendQueue.items.any((i) => i.chatId == widget.chatId))
              Material(
                color: theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.schedule_send),
                  title: Text(
                    '${sendQueue.items.where((i) => i.chatId == widget.chatId).length} queued',
                  ),
                  trailing: TextButton(
                    onPressed: () => client.flushSendQueue(),
                    child: const Text('Retry all'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        ],
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
              thickness: 1.5,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Unread messages',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
              thickness: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
