import 'package:resohertz/pitch/pitch_result.dart';
import 'package:resohertz/tuner/tuning_result.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

/// Pure musical guitar tuner engine.
/// Decouples pitch detection from musical tuning rules, string matching, and cents calculations.
class TunerEngine {
  /// Reference pitch for note A4 in Hertz (standard: 440.0 Hz).
  final double referenceA4;

  /// Tolerance window in musical cents to classify as "In Tune" (standard: ±3.0 cents).
  final double inTuneToleranceCents;

  const TunerEngine({
    this.referenceA4 = 440.0,
    this.inTuneToleranceCents = 3.0,
  });

  /// Returns a copy of this [TunerEngine] with optionally updated parameters.
  TunerEngine copyWith({double? referenceA4, double? inTuneToleranceCents}) {
    return TunerEngine(
      referenceA4: referenceA4 ?? this.referenceA4,
      inTuneToleranceCents: inTuneToleranceCents ?? this.inTuneToleranceCents,
    );
  }

  /// Evaluates an incoming [pitchResult] against the specified [preset] (default: standard tuning).
  /// If [referenceA4] is provided, it overrides this engine's default [referenceA4].
  TuningResult evaluate({
    required PitchResult pitchResult,
    TuningPreset preset = TuningPreset.standard,
    double? referenceA4,
  }) {
    if (!pitchResult.isPitched || pitchResult.frequency <= 0.0) {
      return const TuningResult.unpitched();
    }

    final effectiveA4 = referenceA4 ?? this.referenceA4;
    final detectedFreq = pitchResult.frequency;
    final closestString = preset.findClosestString(
      detectedFreq,
      referenceA4: effectiveA4,
    );
    final targetFreq = closestString.frequencyAt(effectiveA4);
    final cents = TuningResult.calculateCents(detectedFreq, targetFreq);
    final status = TuningResult.determineStatus(
      cents,
      toleranceCents: inTuneToleranceCents,
    );

    return TuningResult(
      targetString: closestString,
      targetFrequency: targetFreq,
      detectedFrequency: detectedFreq,
      centsDifference: cents,
      status: status,
      confidence: pitchResult.confidence,
      isPitched: true,
    );
  }
}
