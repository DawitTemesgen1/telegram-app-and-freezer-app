import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../tdlib/telegram_client.dart';
import '../../utils/app_snack.dart';

class StickerPickerSheet extends StatefulWidget {
  const StickerPickerSheet({
    super.key,
    required this.chatId,
    this.onEmojiSticker,
  });

  final int chatId;
  final void Function(String emoji)? onEmojiSticker;

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet> {
  List<({int setId, String title})> _sets = const [];
  List<({int stickerId, int fileId, String emoji, int width, int height})> _stickers = const [];
  int? _selectedSetId;
  bool _loading = true;

  static const _fallbackEmoji = [
    '😀', '😂', '❤️', '🔥', '👍', '🎉', '😎', '🤔',
    '😢', '😡', '👋', '🙏', '💯', '✨', '🫡', '😴',
  ];

  @override
  void initState() {
    super.initState();
    _loadSets();
  }

  Future<void> _loadSets() async {
    final client = context.read<TelegramClient>();
    final sets = await client.getInstalledStickerSets();
    if (!mounted) return;
    setState(() {
      _sets = sets;
      _loading = false;
    });
    if (sets.isNotEmpty) {
      await _loadStickers(sets.first.setId);
    }
  }

  Future<void> _loadStickers(int setId) async {
    setState(() {
      _selectedSetId = setId;
      _loading = true;
    });
    final client = context.read<TelegramClient>();
    final stickers = await client.getStickersInSet(setId);
    if (!mounted) return;
    setState(() {
      _stickers = stickers;
      _loading = false;
    });
  }

  Future<void> _sendSticker(
    int fileId,
    String emoji,
    int width,
    int height,
  ) async {
    final client = context.read<TelegramClient>();
    final ok = await client.sendSticker(
      widget.chatId,
      fileId,
      emoji: emoji,
      width: width,
      height: height,
    );
    if (mounted && !ok) {
      showAppSnack(context, 'Could not send sticker', error: true);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Stickers', style: theme.textTheme.titleMedium),
            ),
            if (_sets.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _sets.length,
                  itemBuilder: (context, i) {
                    final set = _sets[i];
                    final selected = set.setId == _selectedSetId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(set.title, maxLines: 1),
                        selected: selected,
                        onSelected: (_) => _loadStickers(set.setId),
                      ),
                    );
                  },
                ),
              ),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_stickers.isNotEmpty)
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _stickers.length,
                  itemBuilder: (context, i) {
                    final s = _stickers[i];
                    return InkWell(
                      onTap: () => _sendSticker(
                        s.fileId,
                        s.emoji,
                        s.width,
                        s.height,
                      ),
                      child: Center(
                        child: Text(s.emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    );
                  },
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Recent emoji stickers',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                  ),
                  itemCount: _fallbackEmoji.length,
                  itemBuilder: (context, i) {
                    final e = _fallbackEmoji[i];
                    return InkWell(
                      onTap: () {
                        widget.onEmojiSticker?.call(e);
                        Navigator.pop(context);
                      },
                      child: Center(
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
