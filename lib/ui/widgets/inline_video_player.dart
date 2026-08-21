import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    super.key,
    required this.path,
    this.autoPlay = false,
    this.loop = false,
  });

  final String path;
  final bool autoPlay;
  final bool loop;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.file(File(widget.path));
      await c.initialize();
      c.setLooping(widget.loop);
      if (widget.autoPlay) await c.play();
      c.addListener(() {
        if (mounted) setState(() {});
      });
      if (mounted) {
        setState(() {
          _controller = c;
          _ready = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Cannot play video: $_error'),
      );
    }
    if (!_ready || _controller == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final c = _controller!;
    final aspect = c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                if (!c.value.isPlaying)
                  IconButton.filled(
                    iconSize: 48,
                    onPressed: c.play,
                    icon: const Icon(Icons.play_arrow),
                  ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                if (c.value.isPlaying) {
                  c.pause();
                } else {
                  c.play();
                }
              },
            ),
            Expanded(
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
