import 'package:flutter/services.dart';

/// Result of checking and initializing microphone hardware capabilities.
class MicrophoneInitResult {
  final bool isAvailable;
  final int sampleRate;
  final int minBufferSize;
  final String? error;

  const MicrophoneInitResult({
    required this.isAvailable,
    required this.sampleRate,
    required this.minBufferSize,
    this.error,
  });

  factory MicrophoneInitResult.fromMap(Map<dynamic, dynamic> map) {
    return MicrophoneInitResult(
      isAvailable: map['isAvailable'] as bool? ?? false,
      sampleRate: map['sampleRate'] as int? ?? 44100,
      minBufferSize: map['minBufferSize'] as int? ?? 0,
      error: map['error'] as String?,
    );
  }

  @override
  String toString() {
    return 'MicrophoneInitResult(isAvailable: $isAvailable, sampleRate: $sampleRate, minBufferSize: $minBufferSize, error: $error)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MicrophoneInitResult &&
          runtimeType == other.runtimeType &&
          isAvailable == other.isAvailable &&
          sampleRate == other.sampleRate &&
          minBufferSize == other.minBufferSize &&
          error == other.error;

  @override
  int get hashCode =>
      isAvailable.hashCode ^
      sampleRate.hashCode ^
      minBufferSize.hashCode ^
      error.hashCode;
}

/// Service handling microphone permission and hardware initialization checks.
class MicrophoneService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.resohertz/microphone',
  );

  final MethodChannel _channel;

  const MicrophoneService([MethodChannel? channel])
    : _channel = channel ?? _defaultChannel;

  /// Checks if microphone permission is currently granted.
  Future<bool> checkPermission() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'checkPermission',
      );
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Requests microphone permission from the operating system.
  Future<bool> requestPermission() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'requestPermission',
      );
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Checks microphone hardware compatibility and queries minimum buffer size
  /// for the requested [sampleRate] (defaults to 44100 Hz).
  Future<MicrophoneInitResult> initializeMicrophone({
    int sampleRate = 44100,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('initializeMicrophone', {
            'sampleRate': sampleRate,
          });
      if (result == null) {
        return MicrophoneInitResult(
          isAvailable: false,
          sampleRate: sampleRate,
          minBufferSize: 0,
          error: 'Null response from platform',
        );
      }
      return MicrophoneInitResult.fromMap(result);
    } on PlatformException catch (e) {
      return MicrophoneInitResult(
        isAvailable: false,
        sampleRate: sampleRate,
        minBufferSize: 0,
        error: e.message ?? e.code,
      );
    }
  }
}
