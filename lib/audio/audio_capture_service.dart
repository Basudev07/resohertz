import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Service responsible for managing raw PCM audio capture from native AudioRecord.
class AudioCaptureService {
  static const EventChannel _defaultChannel = EventChannel(
    'com.resohertz/audio_stream',
  );

  final EventChannel _eventChannel;
  final Stream<dynamic>? testStream;

  StreamSubscription<dynamic>? _subscription;
  bool _isCapturing = false;

  AudioCaptureService({EventChannel? eventChannel, this.testStream})
    : _eventChannel = eventChannel ?? _defaultChannel;

  /// Whether audio is actively being captured.
  bool get isCapturing => _isCapturing;

  /// Starts raw audio capture at the specified [sampleRate] (default: 44100 Hz).
  /// Incoming PCM chunks are delivered directly via [onAudioChunk].
  Future<void> startCapture({
    required void Function(Uint8List chunk) onAudioChunk,
    void Function(Object error)? onError,
    int sampleRate = 44100,
  }) async {
    if (_isCapturing) return;

    final stream =
        testStream ??
        _eventChannel.receiveBroadcastStream({'sampleRate': sampleRate});

    _subscription = stream.listen(
      (dynamic data) {
        if (data is Uint8List) {
          onAudioChunk(data);
        } else if (data is List<int>) {
          onAudioChunk(Uint8List.fromList(data));
        }
      },
      onError: (Object error) {
        _isCapturing = false;
        onError?.call(error);
      },
      onDone: () {
        _isCapturing = false;
      },
      cancelOnError: false,
    );

    _isCapturing = true;
  }

  /// Stops audio capture and releases native resources.
  Future<void> stopCapture() async {
    if (!_isCapturing && _subscription == null) return;

    _isCapturing = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes and cancels any active audio subscription.
  void dispose() {
    stopCapture();
  }

  /// Converts raw little-endian PCM byte buffer to a typed [Int16List] view.
  /// Handles both 2-byte aligned buffers and unaligned platform channel buffers safely.
  static Int16List toInt16Samples(Uint8List byteData) {
    if (byteData.lengthInBytes < 2) return Int16List(0);

    // If buffer is 2-byte aligned, zero-copy view is safe
    if (byteData.offsetInBytes % 2 == 0) {
      return byteData.buffer.asInt16List(
        byteData.offsetInBytes,
        byteData.lengthInBytes ~/ 2,
      );
    }

    // Fallback for unaligned buffer using ByteData view
    final numSamples = byteData.lengthInBytes ~/ 2;
    final samples = Int16List(numSamples);
    final bData = ByteData.sublistView(byteData);
    for (int i = 0; i < numSamples; i++) {
      samples[i] = bData.getInt16(i * 2, Endian.little);
    }
    return samples;
  }

  /// Calculates the Root Mean Square (RMS) amplitude of 16-bit signed PCM audio.
  /// Returns a value between 0.0 and 32768.0.
  static double calculateRms(Uint8List byteData) {
    if (byteData.lengthInBytes < 2) return 0.0;

    final samples = toInt16Samples(byteData);
    if (samples.isEmpty) return 0.0;

    double sumSquares = 0.0;
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      sumSquares += sample * sample;
    }

    return math.sqrt(sumSquares / samples.length);
  }

  /// Calculates dBFS (decibels relative to full scale) of 16-bit signed PCM audio.
  /// Returns a value typically between -90.0 dB and 0.0 dB.
  static double calculateDbfs(Uint8List byteData) {
    final rms = calculateRms(byteData);
    if (rms <= 1.0) return -96.0;
    return 20.0 * (math.log(rms / 32768.0) / math.ln10);
  }

  /// Calculates visually responsive audio input level between 0.0 and 1.0.
  /// Uses a logarithmic (decibel) scale from -60 dBFS (ambient silence) to 0 dBFS (peak).
  static double calculateNormalizedLevel(Uint8List byteData) {
    final dbfs = calculateDbfs(byteData);
    // Map -60 dB .. 0 dB to 0.0 .. 1.0
    const minDb = -60.0;
    const maxDb = 0.0;
    if (dbfs <= minDb) return 0.0;
    if (dbfs >= maxDb) return 1.0;
    return (dbfs - minDb) / (maxDb - minDb);
  }
}
