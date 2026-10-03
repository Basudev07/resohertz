import 'dart:math' as math;
import 'dart:typed_data';
import 'package:resohertz/audio/audio_capture_service.dart';
import 'package:resohertz/pitch/pitch_result.dart';

/// Pure Dart implementation of the YIN fundamental frequency estimation algorithm.
/// Optimized for low-latency, zero-allocation real-time guitar pitch detection
/// with sub-harmonic/harmonic rejection, noise-floor prominence gating,
/// and multi-factor confidence evaluation.
class YinPitchDetector {
  final int sampleRate;
  final double threshold;
  final double minFrequency;
  final double maxFrequency;
  final double silenceRmsThreshold;

  final int _minTau;
  final int _maxTau;
  final int _windowSize;
  final Float64List _yinBuffer;

  /// Creates a [YinPitchDetector].
  ///
  /// - [sampleRate]: Sampling rate in Hz (default: 44100).
  /// - [threshold]: Peak picking threshold (default: 0.15).
  /// - [minFrequency]: Minimum detectable frequency in Hz (default: 55.0 Hz, covering Drop D, Drop C, and low tunings).
  /// - [maxFrequency]: Maximum detectable frequency in Hz (default: 1200.0 Hz).
  /// - [silenceRmsThreshold]: Minimum RMS amplitude to attempt pitch detection (default: 50.0).
  YinPitchDetector({
    this.sampleRate = 44100,
    this.threshold = 0.15,
    this.minFrequency = 55.0,
    this.maxFrequency = 1200.0,
    this.silenceRmsThreshold = 75.0,
  }) : _minTau = (sampleRate / maxFrequency).floor(),
       _maxTau = (sampleRate / minFrequency).ceil(),
       _windowSize = 1024,
       _yinBuffer = Float64List((sampleRate / minFrequency).ceil() + 2);

  /// Analyzes a raw 16-bit PCM audio buffer [byteData] and returns a [PitchResult].
  PitchResult detectPitch(Uint8List byteData) {
    if (byteData.lengthInBytes < (_windowSize + _maxTau) * 2) {
      // Need at least windowSize + maxTau samples (1702 samples * 2 = 3404 bytes)
      return const PitchResult.unpitched();
    }

    final samples = AudioCaptureService.toInt16Samples(byteData);
    return detectPitchFromSamples(samples);
  }

  /// Analyzes a typed [Int16List] audio buffer and returns a [PitchResult].
  PitchResult detectPitchFromSamples(Int16List samples) {
    if (samples.length < _windowSize + _maxTau) {
      return const PitchResult.unpitched();
    }

    // Step 0a: Fast energy / silence check & transient / impulse detection
    double sumSquares = 0.0;
    int peakSample = 0;
    int zeroCrossings = 0;
    for (int i = 0; i < _windowSize; i++) {
      final s = samples[i];
      final absS = s.abs();
      if (absS > peakSample) {
        peakSample = absS;
      }
      sumSquares += s * s;
      if (i > 0) {
        final prev = samples[i - 1];
        if ((prev >= 0 && s < 0) || (prev < 0 && s >= 0)) {
          zeroCrossings++;
        }
      }
    }
    final meanSquare = sumSquares > 0 ? (sumSquares / _windowSize) : 0.0;
    if (meanSquare < silenceRmsThreshold * silenceRmsThreshold) {
      return const PitchResult.unpitched();
    }

    // Transient Rejection (Phone taps, surface knocks, table clicks):
    // Periodic musical guitar plucks have moderate crest factor (Peak / RMS ~ 1.4 to 3.0).
    // Sharp non-periodic impulse transients (finger taps on screen/phone, table knocks)
    // have high crest factor (> 3.5) with concentrated impulse energy and silent tail.
    final rmsVal = math.sqrt(meanSquare);
    if (rmsVal > 0) {
      final crestFactor = peakSample / rmsVal;
      if (crestFactor > 3.5) {
        return const PitchResult.unpitched();
      }
    }

    // Step 1: Difference Function
    _yinBuffer[0] = 1.0;
    for (int tau = 1; tau <= _maxTau; tau++) {
      double diffSum = 0.0;
      for (int i = 0; i < _windowSize; i++) {
        final diff = samples[i] - samples[i + tau];
        diffSum += diff * diff;
      }
      _yinBuffer[tau] = diffSum;
    }

    // Step 2: Cumulative Mean Normalized Difference Function (CMNDF)
    double runningSum = 0.0;
    for (int tau = 1; tau <= _maxTau; tau++) {
      runningSum += _yinBuffer[tau];
      if (runningSum > 0.0) {
        _yinBuffer[tau] = (_yinBuffer[tau] * tau) / runningSum;
      } else {
        _yinBuffer[tau] = 1.0;
      }
    }

    // Step 3: Absolute Threshold / Peak Picking
    int tauEstimate = -1;
    for (int tau = _minTau; tau <= _maxTau; tau++) {
      if (_yinBuffer[tau] < threshold) {
        // Find the bottom of the dip (local minimum)
        while (tau + 1 <= _maxTau && _yinBuffer[tau + 1] < _yinBuffer[tau]) {
          tau++;
        }
        tauEstimate = tau;
        break;
      }
    }

    // If no dip was below threshold, find the global minimum within voiced range
    if (tauEstimate == -1) {
      int bestTau = _minTau;
      double minVal = _yinBuffer[_minTau];
      for (int tau = _minTau + 1; tau <= _maxTau; tau++) {
        if (_yinBuffer[tau] < minVal) {
          minVal = _yinBuffer[tau];
          bestTau = tau;
        }
      }

      // If global minimum is too noisy / unvoiced, reject
      if (minVal > 0.20) {
        return const PitchResult.unpitched();
      }
      tauEstimate = bestTau;
    }

    // Step 3b: Harmonic Rejection (Sub-harmonic Multiple Search)
    // Acoustic & electric guitar strings produce strong 2nd and 3rd harmonics.
    // When YIN scans from _minTau upward, it encounters harmonic periods (tau/2, tau/3)
    // first. If a candidate dip is found, inspect integer multiples (2*tau, 3*tau)
    // to check if a deeper or equally valid fundamental cancellation exists.
    final initialTau = tauEstimate;
    int candidateTau = tauEstimate;
    double candidateVal = _yinBuffer[tauEstimate];

    if (candidateVal >= 0.05) {
      for (int k = 2; k <= 3; k++) {
        final targetTau = k * initialTau;
        if (targetTau > _maxTau) break;

        final margin = math.max(3, (targetTau * 0.08).round());
        final startSearch = math.max(_minTau, targetTau - margin);
        final endSearch = math.min(_maxTau, targetTau + margin);

        int bestMultipleTau = targetTau;
        double bestMultipleVal = _yinBuffer[targetTau];

        for (int t = startSearch; t <= endSearch; t++) {
          if (_yinBuffer[t] < bestMultipleVal) {
            bestMultipleVal = _yinBuffer[t];
            bestMultipleTau = t;
          }
        }

        while (bestMultipleTau + 1 <= _maxTau &&
            bestMultipleTau < endSearch + 2 &&
            _yinBuffer[bestMultipleTau + 1] < _yinBuffer[bestMultipleTau]) {
          bestMultipleTau++;
          bestMultipleVal = _yinBuffer[bestMultipleTau];
        }

        // If multiple cancels significantly better (by at least 0.03) and is below threshold:
        if (bestMultipleVal < (candidateVal - 0.03) &&
            bestMultipleVal < threshold) {
          candidateTau = bestMultipleTau;
          candidateVal = bestMultipleVal;
        }
      }
    }
    tauEstimate = candidateTau;

    // Step 3c: Prominence & Noise Floor Validation
    // A genuine musical pitch has a sharp, prominent notch.
    // Room noise or wideband hiss produces shallow, flat valleys.
    final searchHalf = (tauEstimate * 0.5).round();
    final leftStart = math.max(_minTau, tauEstimate - searchHalf);
    final rightEnd = math.min(_maxTau, tauEstimate + searchHalf);

    double peakLeft = _yinBuffer[tauEstimate];
    for (int t = leftStart; t < tauEstimate; t++) {
      if (_yinBuffer[t] > peakLeft) peakLeft = _yinBuffer[t];
    }

    double peakRight = _yinBuffer[tauEstimate];
    for (int t = tauEstimate + 1; t <= rightEnd; t++) {
      if (_yinBuffer[t] > peakRight) peakRight = _yinBuffer[t];
    }

    final dipVal = _yinBuffer[tauEstimate];
    final double prominence;
    if (tauEstimate - _minTau < 10) {
      prominence = peakRight - dipVal;
    } else if (_maxTau - tauEstimate < 10) {
      prominence = peakLeft - dipVal;
    } else {
      prominence = math.min(peakLeft, peakRight) - dipVal;
    }

    if (prominence < 0.18 || dipVal > 0.32) {
      return const PitchResult.unpitched();
    }

    // Step 4: Parabolic Interpolation for Sub-Sample Accuracy
    double betterTau = tauEstimate.toDouble();
    if (tauEstimate > 1 && tauEstimate < _maxTau) {
      final s0 = _yinBuffer[tauEstimate - 1];
      final s1 = _yinBuffer[tauEstimate];
      final s2 = _yinBuffer[tauEstimate + 1];

      final denominator = 2.0 * (2.0 * s1 - s0 - s2);
      if (denominator.abs() > 1e-9) {
        final delta = (s2 - s0) / denominator;
        if (delta.abs() < 1.0) {
          betterTau += delta;
        }
      }
    }

    if (betterTau <= 0.0) {
      return const PitchResult.unpitched();
    }

    // Step 5: Signal Validation (ZCR & Frequency Bounds)
    final expectedCrossings = (2.0 * _windowSize) / betterTau;
    // Upper ZCR bound: rejects high-frequency noise and hiss
    if (zeroCrossings > (expectedCrossings * 2.8 + 12)) {
      return const PitchResult.unpitched();
    }
    // Lower ZCR bound: rejects DC drift, mic handling rumble, and sub-audible pops
    if (zeroCrossings < (expectedCrossings * 0.30 - 3)) {
      return const PitchResult.unpitched();
    }

    final frequency = sampleRate / betterTau;
    if (frequency < minFrequency || frequency > maxFrequency) {
      return const PitchResult.unpitched();
    }

    // Step 6: Confidence Evaluation
    final confidence = (1.0 - dipVal).clamp(0.0, 1.0);

    return PitchResult(
      frequency: frequency,
      confidence: confidence,
      isPitched: confidence >= 0.68,
    );
  }
}
