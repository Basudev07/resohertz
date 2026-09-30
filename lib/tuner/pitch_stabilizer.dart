import 'package:resohertz/tuner/tuning_result.dart';

/// Lightweight stabilizer for visual pitch indicator positioning.
///
/// Applied strictly AFTER existing pitch confidence validation and BEFORE
/// the cents value is rendered on the visual indicator.
///
/// Features:
/// - Adaptive exponential smoothing: small micro-variations (< 2.5 cents) are
///   heavily smoothed to eliminate jitter; larger pitch movements (> 7.0 cents)
///   respond instantly with minimal delay.
/// - Instant snap on string transition: switching strings or first note attack
///   snaps immediately without visual lag.
/// - Micro dead-band: filters out negligible sub-cent acoustic noise.
/// - Dead-center in-tune anchor: gently locks right at 0.0 when within tolerance
///   so the visual marker sits rock-solid in tune.
class PitchStabilizer {
  double? _smoothedCents;
  int? _lastStringNumber;

  /// Current smoothed cents difference.
  double get smoothedCents => _smoothedCents ?? 0.0;

  /// Whether a valid pitch value is currently tracked.
  bool get hasValue => _smoothedCents != null;

  /// Resets the stabilizer (e.g., when audio capture stops or signal is lost).
  void reset() {
    _smoothedCents = null;
    _lastStringNumber = null;
  }

  /// Ingests the latest [TuningResult] and returns the stabilized cents value
  /// to position the visual indicator.
  double update(TuningResult result) {
    if (!result.isPitched) {
      _smoothedCents = null;
      _lastStringNumber = null;
      return 0.0;
    }

    final rawCents = result.centsDifference;
    final currentStringNumber = result.targetString?.stringNumber;

    // If first pitched detection or target string changed, snap immediately
    if (_smoothedCents == null || _lastStringNumber != currentStringNumber) {
      _smoothedCents =
          (result.status == TuningStatus.inTune && rawCents.abs() < 0.65)
          ? 0.0
          : rawCents;
      _lastStringNumber = currentStringNumber;
      return _smoothedCents!;
    }

    final delta = (rawCents - _smoothedCents!).abs();

    // Micro dead-band: ignore imperceptible acoustic jitter (< 0.25 cents)
    if (delta < 0.25) {
      return _smoothedCents!;
    }

    // Adaptive alpha smoothing factor calibrated for 60Hz and 120Hz display smoothness:
    // delta < 3.0¢: heavy smoothing (alpha = 0.16) to eliminate fluttering
    // delta 3.0¢ - 10.0¢: smooth progressive transition (alpha = 0.16 .. 0.40)
    // delta >= 10.0¢: responsive tracking for tuning peg adjustments (alpha = 0.50)
    double alpha;
    if (delta < 3.0) {
      alpha = 0.16;
    } else if (delta < 10.0) {
      alpha = 0.16 + 0.24 * ((delta - 3.0) / 7.0);
    } else {
      alpha = 0.50;
    }

    _smoothedCents = _smoothedCents! + alpha * (rawCents - _smoothedCents!);

    // When verified in-tune by the tuner engine and close to center,
    // gently lock to dead-center (0.0 cents) so the marker aligns perfectly
    if (result.status == TuningStatus.inTune && _smoothedCents!.abs() < 0.65) {
      _smoothedCents = 0.0;
    }

    return _smoothedCents!;
  }
}
