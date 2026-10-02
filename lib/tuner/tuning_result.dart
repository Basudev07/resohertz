import 'dart:math' as math;
import 'package:resohertz/tuning/guitar_string.dart';

/// Tuning state relative to target frequency.
enum TuningStatus {
  /// No pitch or signal below noise threshold.
  unpitched,

  /// Pitch is below target frequency (negative cents).
  flat,

  /// Pitch is accurately matched within tolerance (e.g. ±3 cents).
  inTune,

  /// Pitch is above target frequency (positive cents).
  sharp,
}

/// Evaluation result comparing detected pitch against the target guitar string.
class TuningResult {
  /// The matched guitar string (null if unpitched).
  final GuitarString? targetString;

  /// The theoretical target frequency in Hertz.
  final double targetFrequency;

  /// The live detected frequency in Hertz.
  final double detectedFrequency;

  /// The difference in musical cents: 1200 * log2(detected / target).
  /// Negative = flat, 0 = matched, positive = sharp.
  final double centsDifference;

  /// Classification: inTune, flat, sharp, or unpitched.
  final TuningStatus status;

  /// Pitch confidence score from the detector (0.0 to 1.0).
  final double confidence;

  /// Whether a valid pitch was detected.
  final bool isPitched;

  const TuningResult({
    required this.targetString,
    required this.targetFrequency,
    required this.detectedFrequency,
    required this.centsDifference,
    required this.status,
    required this.confidence,
    required this.isPitched,
  });

  /// Represents an unpitched or idle tuning state.
  const TuningResult.unpitched()
    : targetString = null,
      targetFrequency = 0.0,
      detectedFrequency = 0.0,
      centsDifference = 0.0,
      status = TuningStatus.unpitched,
      confidence = 0.0,
      isPitched = false;

  /// Calculates cents difference between [detectedFrequency] and [targetFrequency].
  /// Formula: 1200 * log2(detected / target).
  static double calculateCents(
    double detectedFrequency,
    double targetFrequency,
  ) {
    if (detectedFrequency <= 0.0 || targetFrequency <= 0.0) return 0.0;
    return 1200.0 * (math.log(detectedFrequency / targetFrequency) / math.ln2);
  }

  /// Determines [TuningStatus] based on [centsDifference] and [toleranceCents].
  static TuningStatus determineStatus(
    double centsDifference, {
    double toleranceCents = 3.0,
  }) {
    if (centsDifference.abs() <= toleranceCents) {
      return TuningStatus.inTune;
    } else if (centsDifference < -toleranceCents) {
      return TuningStatus.flat;
    } else {
      return TuningStatus.sharp;
    }
  }

  /// Determines [TuningStatus] with hysteresis to prevent rapid boundary oscillation.
  ///
  /// - When transitioning INTO [TuningStatus.inTune], requires |centsDifference| <= [toleranceCents].
  /// - When already in [TuningStatus.inTune], requires |centsDifference| > ([toleranceCents] + [hysteresisCents])
  ///   to transition back to flat or sharp.
  static TuningStatus determineStatusWithHysteresis(
    double centsDifference, {
    required TuningStatus previousStatus,
    double toleranceCents = 3.0,
    double hysteresisCents = 1.0,
  }) {
    final effectiveTolerance = previousStatus == TuningStatus.inTune
        ? (toleranceCents + hysteresisCents)
        : toleranceCents;

    if (centsDifference.abs() <= effectiveTolerance) {
      return TuningStatus.inTune;
    } else if (centsDifference < -effectiveTolerance) {
      return TuningStatus.flat;
    } else {
      return TuningStatus.sharp;
    }
  }

  @override
  String toString() {
    if (!isPitched) return 'TuningResult.unpitched';
    return 'TuningResult(${targetString?.displayName}: ${detectedFrequency.toStringAsFixed(1)} / ${targetFrequency.toStringAsFixed(1)} Hz, ${centsDifference >= 0 ? '+' : ''}${centsDifference.toStringAsFixed(1)} cents, $status)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TuningResult &&
          runtimeType == other.runtimeType &&
          targetString == other.targetString &&
          (targetFrequency - other.targetFrequency).abs() < 0.001 &&
          (detectedFrequency - other.detectedFrequency).abs() < 0.001 &&
          (centsDifference - other.centsDifference).abs() < 0.001 &&
          status == other.status &&
          (confidence - other.confidence).abs() < 0.001 &&
          isPitched == other.isPitched;

  @override
  int get hashCode =>
      targetString.hashCode ^
      targetFrequency.hashCode ^
      detectedFrequency.hashCode ^
      centsDifference.hashCode ^
      status.hashCode ^
      confidence.hashCode ^
      isPitched.hashCode;
}
