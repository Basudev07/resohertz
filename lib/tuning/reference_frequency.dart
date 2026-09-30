/// Constants and utilities for concert pitch reference frequencies (A4).
class ReferenceFrequency {
  /// Standard concert pitch (ISO 16 standard).
  static const double standard = 440.0;

  /// Verdi / Philosophical / Scientific pitch.
  static const double verdi = 432.0;

  /// European orchestral pitch.
  static const double orchestral = 442.0;

  /// Minimum permitted reference frequency (covers historical Baroque pitch).
  static const double minAllowed = 415.0;

  /// Maximum permitted reference frequency (covers high Chorton pitch).
  static const double maxAllowed = 466.0;

  /// Common quick-select reference frequency presets.
  static const List<double> commonPresets = [432.0, 440.0, 442.0];

  /// Clamps the given [frequency] to the valid reference frequency range [minAllowed, maxAllowed].
  static double clamp(double frequency) {
    return frequency.clamp(minAllowed, maxAllowed);
  }

  /// Formats a reference frequency as a clean string (e.g., '440 Hz' or '440.5 Hz').
  static String format(double frequency) {
    if (frequency == frequency.roundToDouble()) {
      return '${frequency.toInt()} Hz';
    }
    return '${frequency.toStringAsFixed(1)} Hz';
  }
}
