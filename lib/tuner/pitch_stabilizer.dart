import 'package:resohertz/tuner/tuning_result.dart';

/// Lightweight stabilizer for visual pitch indicator positioning.
///
/// Applied strictly AFTER existing pitch confidence validation and BEFORE
/// the cents value is rendered on the visual indicator.
///
/// Features:
/// - Adaptive exponential smoothing: small micro-variations (< 2.5 cents) are
///   heavily smoothed to eliminate jitter; larger pitch movements (> 7.0 cents)
///   respond swiftly with minimal delay.
/// - Rapid target acquisition on string transition: switching strings or first note attack
///   initializes target position immediately for smooth animation.
/// - Micro dead-band: filters out negligible sub-cent acoustic noise.
/// - Authentic pitch fidelity: accurately preserves cents difference without
///   artificially forcing or clamping the indicator to 0.0.
class PitchStabilizer {
  /// Temporary hold duration during string decay before resetting to idle.
  final Duration holdDuration;

  double? _smoothedCents;
  int? _lastStringNumber;
  TuningResult? _lastReliableResult;
  DateTime? _lastPitchedTimestamp;
  bool _isHolding = false;

  double? _lastDeltaSign;

  PitchStabilizer({
    this.holdDuration = const Duration(milliseconds: 300),
  });

  /// Current smoothed cents difference.
  double get smoothedCents => _smoothedCents ?? 0.0;

  /// Whether a valid pitch value is currently tracked (either actively or during hold).
  bool get hasValue => _smoothedCents != null;

  /// Whether the stabilizer is currently holding the last reliable reading
  /// because the signal is temporarily weak or decaying.
  bool get isHolding => _isHolding;

  /// The most recent reliable [TuningResult] before any signal fading or hold.
  TuningResult? get lastReliableResult => _lastReliableResult;

  /// Resets the stabilizer (e.g., when audio capture stops or signal is lost).
  void reset() {
    _smoothedCents = null;
    _lastStringNumber = null;
    _lastReliableResult = null;
    _lastPitchedTimestamp = null;
    _isHolding = false;
    _lastDeltaSign = null;
  }

  /// Ingests the latest [TuningResult] and returns the stabilized cents value
  /// to position the visual indicator.
  ///
  /// - When [result.isPitched] is true, smoothly tracks pitch changes.
  /// - When [result.isPitched] is false, holds the last reliable reading for [holdDuration]
  ///   to prevent visual jumpiness during string decay before returning to 0.0.
  double update(TuningResult result, {DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();

    if (!result.isPitched) {
      if (_smoothedCents != null && holdDuration > Duration.zero) {
        if (_lastPitchedTimestamp != null &&
            now.difference(_lastPitchedTimestamp!) < holdDuration) {
          _isHolding = true;
          return _smoothedCents!;
        }
      }
      reset();
      return 0.0;
    }

    final rawCents = result.centsDifference;
    final currentStringNumber = result.targetString?.stringNumber;

    // Track reliable state
    _lastReliableResult = result;
    _lastPitchedTimestamp = now;
    _isHolding = false;

    // If first pitched detection or target string changed, initialize tracking
    if (_smoothedCents == null || _lastStringNumber != currentStringNumber) {
      _smoothedCents = rawCents;
      _lastStringNumber = currentStringNumber;
      _lastDeltaSign = null;
      return _smoothedCents!;
    }

    final diff = rawCents - _smoothedCents!;
    final delta = diff.abs();

    // Micro dead-band: ignore imperceptible acoustic jitter (< 0.25 cents)
    if (delta < 0.25) {
      return _smoothedCents!;
    }

    // Direction-reversal detection: detects when incoming pitch alternates sign around smoothed value
    // (the classic hallmark of acoustic phase interference and noise during string decay)
    final currentDeltaSign = diff > 0 ? 1.0 : -1.0;
    final isDirectionFlip = _lastDeltaSign != null && _lastDeltaSign != currentDeltaSign;
    _lastDeltaSign = currentDeltaSign;

    // Adaptive alpha smoothing factor calibrated for 60Hz and 120Hz display smoothness:
    // delta < 3.0¢: heavy smoothing (alpha = 0.16) to eliminate fluttering
    // delta 3.0¢ - 10.0¢: smooth progressive transition (alpha = 0.16 .. 0.40)
    // delta >= 10.0¢: responsive tracking for tuning peg adjustments (alpha = 0.50)
    double alpha;
    if (delta < 3.0) {
      alpha = 0.16;
      // Anti-fluttering during decay:
      // When alternating directions within micro-range (< 2.0¢), strongly damp
      // to eliminate rapid left-right wobble while preserving genuine peg adjustments.
      if (isDirectionFlip && delta < 2.0) {
        alpha = 0.04;
      } else if (_smoothedCents!.abs() < 2.0 && rawCents.abs() < 2.0) {
        // When about to be tuned (within ±2¢ of center), heavily stabilize against room noise
        alpha = 0.07;
      }
    } else if (delta < 10.0) {
      alpha = 0.16 + 0.24 * ((delta - 3.0) / 7.0);
    } else {
      alpha = 0.50;
    }

    _smoothedCents = _smoothedCents! + alpha * diff;

    return _smoothedCents!;
  }
}
