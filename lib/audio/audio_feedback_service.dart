import 'dart:async';
import 'package:flutter/services.dart';

/// Service responsible for triggering in-tune audio feedback.
///
/// Communicates over the 'com.resohertz/audio_feedback' platform channel
/// to play the bundled 'lib/audio/success.mp3' when a note enters in-tune status.
///
/// Features acoustic feedback & resonance protection:
/// 1. Tracks [isPlaying] state during chime playback and room reverb decay.
/// 2. Enforces a minimum cooldown ([minInterval]) between audio triggers.
class AudioFeedbackService {
  static const String channelName = 'com.resohertz/audio_feedback';
  static const MethodChannel _defaultChannel = MethodChannel(channelName);

  final MethodChannel _channel;
  bool _isPlaying = false;
  DateTime? _lastPlayTime;
  Timer? _playbackTimer;

  AudioFeedbackService([MethodChannel? channel])
    : _channel = channel ?? _defaultChannel;

  /// Whether the in-tune feedback sound is currently playing or in room decay blanking.
  bool get isPlaying => _isPlaying;

  /// Plays the bundled 'lib/audio/success.mp3' once.
  ///
  /// Ignores requests if audio feedback is already actively sounding,
  /// or if triggered within [minInterval] of the last playback.
  Future<void> playInTuneSound({
    Duration minInterval = const Duration(milliseconds: 2000),
  }) async {
    final now = DateTime.now();
    if (_isPlaying) return;
    if (_lastPlayTime != null && now.difference(_lastPlayTime!) < minInterval) {
      return;
    }

    _isPlaying = true;
    _lastPlayTime = now;

    try {
      final dynamic result = await _channel.invokeMethod('playInTuneSound');
      final durationMs = (result is int && result > 0) ? result : 1200;
      _playbackTimer?.cancel();
      _playbackTimer = Timer(Duration(milliseconds: durationMs + 250), () {
        _isPlaying = false;
      });
    } catch (_) {
      // Graceful fallback for mock tests or platforms without native implementation
      _playbackTimer?.cancel();
      _playbackTimer = Timer(const Duration(milliseconds: 300), () {
        _isPlaying = false;
      });
    }
  }

  /// Cancels active timers and resets playing/cooldown states.
  void reset() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _isPlaying = false;
    _lastPlayTime = null;
  }
}
