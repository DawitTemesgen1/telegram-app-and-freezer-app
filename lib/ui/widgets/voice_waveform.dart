import 'dart:math';

import 'package:flutter/material.dart';

/// Simple animated bars for voice recording/playback.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.active,
    this.barCount = 24,
    this.progress,
    this.color,
  });

  final bool active;
  final int barCount;
  final double? progress;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    final played = progress ?? (active ? null : 1.0);

    return SizedBox(
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(barCount, (i) {
          final seed = (i * 17 + 3) % 11;
          final h = 6.0 + seed * 1.8;
          final filled = played == null
              ? active
              : (i / barCount) <= played;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: AnimatedContainer(
                duration: Duration(milliseconds: active ? 120 + seed * 8 : 200),
                height: active ? h + (seed % 3) * 2 : h,
                decoration: BoxDecoration(
                  color: filled
                      ? c
                      : c.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

String formatVoiceDuration(Duration d) {
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Fake waveform heights from byte samples (or random if empty).
List<double> waveformFromString(String? waveform, {int count = 24}) {
  if (waveform == null || waveform.isEmpty) {
    final rng = Random(42);
    return List.generate(count, (_) => 0.2 + rng.nextDouble() * 0.8);
  }
  final bytes = waveform.codeUnits;
  if (bytes.isEmpty) {
    return List.generate(count, (i) => 0.3 + (i % 5) * 0.1);
  }
  return List.generate(count, (i) {
    final b = bytes[i * bytes.length ~/ count % bytes.length];
    return (b / 255).clamp(0.15, 1.0);
  });
}
