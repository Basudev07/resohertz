/// Result of a pitch detection operation.
class PitchResult {
  /// Detected fundamental frequency in Hertz (Hz). 0.0 if unpitched.
  final double frequency;

  /// Confidence score between 0.0 (no periodicity) and 1.0 (pure tone).
  final double confidence;

  /// Whether a valid pitch was confidently detected above the noise floor.
  final bool isPitched;

  const PitchResult({
    required this.frequency,
    required this.confidence,
    required this.isPitched,
  });

  /// Represents an unpitched or silent audio frame.
  const PitchResult.unpitched()
    : frequency = 0.0,
      confidence = 0.0,
      isPitched = false;

  @override
  String toString() {
    if (!isPitched) return 'PitchResult.unpitched';
    return 'PitchResult(frequency: ${frequency.toStringAsFixed(1)} Hz, confidence: ${(confidence * 100).toStringAsFixed(0)}%)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchResult &&
          runtimeType == other.runtimeType &&
          (frequency - other.frequency).abs() < 0.001 &&
          (confidence - other.confidence).abs() < 0.001 &&
          isPitched == other.isPitched;

  @override
  int get hashCode =>
      frequency.hashCode ^ confidence.hashCode ^ isPitched.hashCode;
}
