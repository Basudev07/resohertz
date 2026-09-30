import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/audio/audio_capture_service.dart';

void main() {
  group('AudioCaptureService - Mathematical calculations', () {
    test(
      'calculateRms, dBFS, and normalized level on silent buffer (zeros)',
      () {
        final buffer = Uint8List(100); // All zeros
        final rms = AudioCaptureService.calculateRms(buffer);
        final dbfs = AudioCaptureService.calculateDbfs(buffer);
        final level = AudioCaptureService.calculateNormalizedLevel(buffer);

        expect(rms, 0.0);
        expect(dbfs, -96.0);
        expect(level, 0.0);
      },
    );

    test('calculateRms on empty or single-byte buffer returns 0.0', () {
      expect(AudioCaptureService.calculateRms(Uint8List(0)), 0.0);
      expect(AudioCaptureService.calculateRms(Uint8List(1)), 0.0);
      expect(AudioCaptureService.calculateDbfs(Uint8List(0)), -96.0);
    });

    test('calculateRms and dBFS on constant DC value', () {
      // Create 16-bit PCM values with constant value 1000
      final byteData = ByteData(4); // 2 samples
      byteData.setInt16(0, 1000, Endian.little);
      byteData.setInt16(2, 1000, Endian.little);

      final uint8 = byteData.buffer.asUint8List();
      final rms = AudioCaptureService.calculateRms(uint8);
      final dbfs = AudioCaptureService.calculateDbfs(uint8);
      final level = AudioCaptureService.calculateNormalizedLevel(uint8);

      expect(rms, closeTo(1000.0, 0.001));
      // 20 * log10(1000 / 32768) ≈ -30.3 dBFS
      expect(dbfs, closeTo(-30.3, 0.1));
      // Level = (-30.3 + 60) / 60 ≈ 0.495
      expect(level, closeTo(0.495, 0.01));
    });

    test(
      'toInt16Samples correctly interprets 16-bit little-endian samples',
      () {
        final byteData = ByteData(4);
        byteData.setInt16(0, -32768, Endian.little);
        byteData.setInt16(2, 32767, Endian.little);

        final samples = AudioCaptureService.toInt16Samples(
          byteData.buffer.asUint8List(),
        );
        expect(samples.length, 2);
        expect(samples[0], -32768);
        expect(samples[1], 32767);
      },
    );

    test('toInt16Samples handles unaligned byte buffer safely', () {
      // Create a 5-byte buffer and slice from offset 1 (odd alignment)
      final raw = Uint8List(6);
      final bData = ByteData.sublistView(raw);
      bData.setInt16(1, 1234, Endian.little);
      bData.setInt16(3, -5678, Endian.little);

      // Sublist view starting at odd offset 1
      final unaligned = raw.sublist(1, 5);
      final samples = AudioCaptureService.toInt16Samples(unaligned);

      expect(samples.length, 2);
      expect(samples[0], 1234);
      expect(samples[1], -5678);
    });
  });

  group('AudioCaptureService - Stream lifecycle', () {
    test(
      'startCapture delivers audio chunks and updates isCapturing',
      () async {
        final controller = StreamController<dynamic>();
        final service = AudioCaptureService(testStream: controller.stream);

        expect(service.isCapturing, isFalse);

        final receivedChunks = <Uint8List>[];

        await service.startCapture(onAudioChunk: receivedChunks.add);
        expect(service.isCapturing, isTrue);

        final chunk1 = Uint8List.fromList([1, 2, 3, 4]);
        final chunk2 = Uint8List.fromList([5, 6, 7, 8]);
        controller.add(chunk1);
        controller.add(chunk2);

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(receivedChunks.length, 2);
        expect(receivedChunks[0], chunk1);
        expect(receivedChunks[1], chunk2);

        await service.stopCapture();
        expect(service.isCapturing, isFalse);

        service.dispose();
        await controller.close();
      },
    );

    test('handles stream errors cleanly', () async {
      final controller = StreamController<dynamic>();
      final service = AudioCaptureService(testStream: controller.stream);

      Object? receivedError;

      await service.startCapture(
        onAudioChunk: (_) {},
        onError: (Object err) {
          receivedError = err;
        },
      );
      expect(service.isCapturing, isTrue);

      controller.addError('Audio hardware error');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(service.isCapturing, isFalse);
      expect(receivedError, 'Audio hardware error');

      service.dispose();
      await controller.close();
    });
  });
}
