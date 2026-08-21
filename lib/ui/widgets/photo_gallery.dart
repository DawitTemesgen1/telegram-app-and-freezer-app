import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../tdlib/telegram_client.dart';

class PhotoGalleryViewer extends StatefulWidget {
  const PhotoGalleryViewer({
    super.key,
    required this.messages,
    required this.initialIndex,
  });

  final List<FocusMessage> messages;
  final int initialIndex;

  @override
  State<PhotoGalleryViewer> createState() => _PhotoGalleryViewerState();
}

class _PhotoGalleryViewerState extends State<PhotoGalleryViewer> {
  late final PageController _pageController;
  final Map<int, String?> _paths = {};
  final Map<int, bool> _loading = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _load(widget.initialIndex);
  }

  Future<void> _load(int index) async {
    if (index < 0 || index >= widget.messages.length) return;
    if (_paths.containsKey(index) || _loading[index] == true) return;
    setState(() => _loading[index] = true);
    final fileId = widget.messages[index].mediaFileId;
    if (fileId == null) {
      setState(() {
        _loading[index] = false;
        _paths[index] = null;
      });
      return;
    }
    final path = await context.read<TelegramClient>().downloadFile(fileId);
    if (!mounted) return;
    setState(() {
      _loading[index] = false;
      _paths[index] = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.initialIndex + 1} / ${widget.messages.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.messages.length,
        onPageChanged: _load,
        itemBuilder: (context, index) {
          final loading = _loading[index] == true;
          final path = _paths[index];
          final caption = widget.messages[index].text;
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : path == null
                          ? const Text(
                              'Could not load',
                              style: TextStyle(color: Colors.white),
                            )
                          : InteractiveViewer(
                              child: Image.file(
                                File(path),
                                fit: BoxFit.contain,
                              ),
                            ),
                ),
              ),
              if (caption.isNotEmpty && caption != '[photo]')
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    caption,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
