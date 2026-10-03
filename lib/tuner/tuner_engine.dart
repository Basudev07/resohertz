import 'package:resohertz/pitch/pitch_result.dart';
import 'package:resohertz/tuner/tuning_result.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

/// Pure musical guitar tuner engine.
/// Decouples pitch detection from musical tuning rules, string matching, and cents calculations.
class TunerEngine {
  /// Reference pitch for note A4 in Hertz (standard: 440.0 Hz).
  final double referenceA4;

  /// Tolerance window in musical cents to classify as "In Tune" (precise: ±1.0 cent).
  final double inTuneToleranceCents;

  const TunerEngine({
    this.referenceA4 = 440.0,
    this.inTuneToleranceCents = 1.0,
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
  /// If [previousStatus] is provided, evaluates with hysteresis to prevent rapid boundary toggling.
  TuningResult evaluate({
    required PitchResult pitchResult,
    TuningPreset preset = TuningPreset.standard,
    double? referenceA4,
    TuningStatus? previousStatus,
    double hysteresisCents = 0.25,
  }) {
    if (!pitchResult.isPitched || pitchResult.frequency <= 0.0) {
      return const TuningResult.unpitched();
    }

    final effectiveA4 = referenceA4 ?? this.referenceA4;
    final detectedFreq = pitchResult.frequency;

    // Plausible guitar range check: covers low Drop C (~65.4 Hz, or down to 50 Hz for extreme tunings)
    // up to high fret positions (~850 Hz). Rejects high environmental whistles, speech sibilance, etc.
    if (detectedFreq < 50.0 || detectedFreq > 850.0) {
      return const TuningResult.unpitched();
    }

    final closestString = preset.findClosestString(
      detectedFreq,
      referenceA4: effectiveA4,
    );
    final targetFreq = closestString.frequencyAt(effectiveA4);
    final cents = TuningResult.calculateCents(detectedFreq, targetFreq);

    // Selected-string range check: if detected pitch is more than an octave / extreme distance
    // (> 600 cents from nearest string in preset), reject as ambient noise.
    if (cents.abs() > 600.0) {
      return const TuningResult.unpitched();
    }

    final status = previousStatus != null
        ? TuningResult.determineStatusWithHysteresis(
            cents,
            previousStatus: previousStatus,
            toleranceCents: inTuneToleranceCents,
            hysteresisCents: hysteresisCents,
          )
        : TuningResult.determineStatus(
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
