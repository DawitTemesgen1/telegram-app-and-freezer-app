import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'voice_waveform.dart';

class AudioPlayerSheet extends StatefulWidget {
  const AudioPlayerSheet({
    super.key,
    required this.path,
    required this.title,
  });

  final String path;
  final String title;

  @override
  State<AudioPlayerSheet> createState() => _AudioPlayerSheetState();
}

class _AudioPlayerSheetState extends State<AudioPlayerSheet> {
  final _player = AudioPlayer();
  bool _loading = true;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setFilePath(widget.path);
      _duration = _player.duration ?? Duration.zero;
      _player.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _player.playerStateStream.listen((state) {
        if (mounted) {
          setState(() => _playing = state.playing);
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxMs = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const CircularProgressIndicator()
            else ...[
              VoiceWaveform(
                active: _playing,
                progress: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0,
              ),
              const SizedBox(height: 8),
              Slider(
                value: _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
                max: maxMs,
                onChanged: (v) => _player.seek(
                  Duration(milliseconds: v.round()),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(_position), style: theme.textTheme.labelSmall),
                  Text(_fmt(_duration), style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 8),
              IconButton.filled(
                iconSize: 36,
                onPressed: () {
                  if (_playing) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
