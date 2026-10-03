import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/pitch/pitch_result.dart';
import 'package:resohertz/pitch/yin_pitch_detector.dart';

/// Helper to generate pure sine wave PCM 16-bit audio buffers for testing.
Uint8List generateSineWave({
  required double frequency,
  int sampleRate = 44100,
  int numSamples = 2048,
  double amplitude = 0.8,
}) {
  final buffer = ByteData(numSamples * 2);
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final sample = (math.sin(2 * math.pi * frequency * t) * amplitude * 32767)
        .round();
    buffer.setInt16(i * 2, sample, Endian.little);
  }
  return buffer.buffer.asUint8List();
}

/// Helper to generate multi-harmonic audio buffers (fundamental + harmonics).
Uint8List generateHarmonicTone({
  required double fundamental,
  required List<double> harmonicAmplitudes,
  int sampleRate = 44100,
  int numSamples = 2048,
}) {
  final buffer = ByteData(numSamples * 2);
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    double sampleVal = 0.0;
    for (int h = 0; h < harmonicAmplitudes.length; h++) {
      final harmonicNumber = h + 1;
      final amp = harmonicAmplitudes[h];
      sampleVal +=
          amp * math.sin(2 * math.pi * (fundamental * harmonicNumber) * t);
    }
    final intSample = (sampleVal * 32767).clamp(-32768.0, 32767.0).round();
    buffer.setInt16(i * 2, intSample, Endian.little);
  }
  return buffer.buffer.asUint8List();
}

void main() {
  late YinPitchDetector detector;

  setUp(() {
    detector = YinPitchDetector(sampleRate: 44100);
  });

  group('YinPitchDetector - Standard Guitar String Fundamentals', () {
    test('detects E2 (82.41 Hz - String 6) accurately', () {
      const targetFreq = 82.407;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.5));
      expect(result.confidence, greaterThan(0.90));
    });

    test('detects A2 (110.00 Hz - String 5) accurately', () {
      const targetFreq = 110.00;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.4));
      expect(result.confidence, greaterThan(0.90));
    });

    test('detects D3 (146.83 Hz - String 4) accurately', () {
      const targetFreq = 146.832;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.4));
      expect(result.confidence, greaterThan(0.90));
    });

    test('detects G3 (196.00 Hz - String 3) accurately', () {
      const targetFreq = 195.998;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.4));
      expect(result.confidence, greaterThan(0.90));
    });

    test('detects B3 (246.94 Hz - String 2) accurately', () {
      const targetFreq = 246.942;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.4));
      expect(result.confidence, greaterThan(0.90));
    });

    test('detects E4 (329.63 Hz - String 1) accurately', () {
      const targetFreq = 329.628;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.5));
      expect(result.confidence, greaterThan(0.90));
    });

    test('detects A4 (440.00 Hz - Concert Pitch) accurately', () {
      const targetFreq = 440.00;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.5));
      expect(result.confidence, greaterThan(0.90));
    });

    test('detects D2 (73.42 Hz - Drop D low string) accurately', () {
      const targetFreq = 73.416;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.5));
      expect(result.confidence, greaterThan(0.85));
    });

    test('detects C2 (65.41 Hz - Drop C low string) accurately', () {
      const targetFreq = 65.406;
      final buffer = generateSineWave(frequency: targetFreq);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(targetFreq, 0.5));
      expect(result.confidence, greaterThan(0.80));
    });
  });

  group('YinPitchDetector - Noise and Silence Rejection', () {
    test('returns unpitched for silent buffer (all zeros)', () {
      final buffer = Uint8List(2048 * 2);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isFalse);
      expect(result.frequency, 0.0);
    });

    test(
      'returns unpitched for buffer smaller than minimum required window',
      () {
        final buffer = Uint8List(500);
        final result = detector.detectPitch(buffer);

        expect(result.isPitched, isFalse);
      },
    );

    test('returns unpitched for random white noise', () {
      final rng = math.Random(42);
      final buffer = ByteData(2048 * 2);
      for (int i = 0; i < 2048; i++) {
        buffer.setInt16(i * 2, rng.nextInt(65536) - 32768, Endian.little);
      }

      final result = detector.detectPitch(buffer.buffer.asUint8List());
      expect(result.isPitched, isFalse);
    });

    test('returns unpitched for low-level room noise below threshold', () {
      final rng = math.Random(123);
      final buffer = ByteData(2048 * 2);
      for (int i = 0; i < 2048; i++) {
        // Low amplitude noise (RMS ~20, well below 50.0 threshold)
        buffer.setInt16(i * 2, rng.nextInt(70) - 35, Endian.little);
      }

      final result = detector.detectPitch(buffer.buffer.asUint8List());
      expect(result.isPitched, isFalse);
      expect(result.frequency, 0.0);
    });

    test(
      'returns unpitched for high-frequency noise with excess zero crossings',
      () {
        // 5500 Hz high hiss (far beyond guitar register and excessive ZCR)
        final buffer = generateSineWave(frequency: 5500.0, amplitude: 0.6);
        final result = detector.detectPitch(buffer);
        expect(result.isPitched, isFalse);
      },
    );

    test('returns unpitched for impulsive transient spike (tap or knock)', () {
      final buffer = ByteData(2048 * 2);
      // Sharp impulse spike (e.g. phone tap: single extreme peak with silent tail)
      buffer.setInt16(100 * 2, 28000, Endian.little);
      buffer.setInt16(101 * 2, -18000, Endian.little);
      buffer.setInt16(102 * 2, 6000, Endian.little);

      final result = detector.detectPitch(buffer.buffer.asUint8List());
      expect(result.isPitched, isFalse);
    });

    test('returns unpitched for finger tap on phone body / table thump', () {
      final buffer = ByteData(2048 * 2);
      // Moderately damped mechanical tap (crest factor ~ 4.2)
      for (int i = 0; i < 40; i++) {
        final decay = math.exp(-i / 8.0);
        final sample = (math.sin(i * 0.5) * 4500 * decay).round();
        buffer.setInt16((50 + i) * 2, sample, Endian.little);
      }

      final result = detector.detectPitch(buffer.buffer.asUint8List());
      expect(result.isPitched, isFalse);
    });
  });

  group('YinPitchDetector - Harmonic Rejection & Accuracy', () {
    test(
      'rejects dominant 2nd harmonic and locks to A2 (110 Hz) fundamental',
      () {
        // 2nd harmonic (220 Hz, amp 0.70) is stronger than fundamental (110 Hz, amp 0.40)
        final buffer = generateHarmonicTone(
          fundamental: 110.0,
          harmonicAmplitudes: [0.40, 0.70],
        );
        final result = detector.detectPitch(buffer);

        expect(result.isPitched, isTrue);
        expect(result.frequency, closeTo(110.0, 0.5));
        expect(result.confidence, greaterThan(0.85));
      },
    );

    test(
      'rejects dominant 3rd harmonic and locks to E2 (82.41 Hz) fundamental',
      () {
        // 3rd harmonic (247.2 Hz, amp 0.60) is stronger than fundamental (82.4 Hz, amp 0.35)
        final buffer = generateHarmonicTone(
          fundamental: 82.407,
          harmonicAmplitudes: [0.35, 0.35, 0.60],
        );
        final result = detector.detectPitch(buffer);

        expect(result.isPitched, isTrue);
        expect(result.frequency, closeTo(82.407, 0.6));
        expect(result.confidence, greaterThan(0.80));
      },
    );

    test('does not falsely sub-harmonize high guitar note E4 (329.63 Hz)', () {
      final buffer = generateSineWave(frequency: 329.628);
      final result = detector.detectPitch(buffer);

      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(329.628, 0.5));
      // Ensures it did NOT falsely jump down to E3 (164.8 Hz) or E2 (82.4 Hz)
      expect(result.frequency, greaterThan(300.0));
    });

    test('recovers fundamental frequency even under severe audio clipping', () {
      // Heavily clipped A2 string pluck (overdriven guitar pickup)
      final buffer = ByteData(2048 * 2);
      for (int i = 0; i < 2048; i++) {
        final t = i / 44100.0;
        final raw = math.sin(2 * math.pi * 110.0 * t) * 2.0; // 200% overdrive
        final clipped = (raw.clamp(-1.0, 1.0) * 32767).round();
        buffer.setInt16(i * 2, clipped, Endian.little);
      }

      final result = detector.detectPitch(buffer.buffer.asUint8List());
      expect(result.isPitched, isTrue);
      expect(result.frequency, closeTo(110.0, 0.5));
    });
  });

  group('PitchResult Model', () {
    test('equality and toString format', () {
      const r1 = PitchResult(
        frequency: 440.0,
        confidence: 0.95,
        isPitched: true,
      );
      const r2 = PitchResult(
        frequency: 440.0,
        confidence: 0.95,
        isPitched: true,
      );
      const r3 = PitchResult.unpitched();

      expect(r1, equals(r2));
      expect(r1, isNot(equals(r3)));
      expect(r1.toString(), contains('440.0 Hz'));
      expect(r3.toString(), equals('PitchResult.unpitched'));
    });
  });
}
