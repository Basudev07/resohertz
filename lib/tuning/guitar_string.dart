import 'dart:math' as math;

/// Represents a single guitar string and its target musical pitch.
class GuitarString {
  /// String number from highest pitch to lowest pitch (1 = High E, 6 = Low E).
  final int stringNumber;

  /// Musical note name without octave (e.g., 'E', 'A', 'D', 'G', 'B').
  final String noteName;

  /// Octave number in standard scientific pitch notation (e.g., 2, 3, 4).
  final int octave;

  /// Standard MIDI note number (e.g., E2 = 40, A2 = 45, D3 = 50, G3 = 55, B3 = 59, E4 = 64).
  final int midiNote;

  const GuitarString({
    required this.stringNumber,
    required this.noteName,
    required this.octave,
    required this.midiNote,
  });

  /// Full formatted note label including octave (e.g. "E2", "A2", "E4").
  String get displayName => '$noteName$octave';

  /// Descriptive label with string number (e.g. "6th String (E2)").
  String get fullLabel => 'String $stringNumber ($displayName)';

  /// Calculates the exact equal-temperament target frequency in Hertz for this string,
  /// relative to the given [referenceA4] frequency (standard: 440.0 Hz).
  ///
  /// Uses the equal-temperament formula:
  /// f = A4 * 2^((midiNote - 69) / 12)
  double frequencyAt([double referenceA4 = 440.0]) {
    return referenceA4 * math.pow(2.0, (midiNote - 69) / 12.0);
  }

  /// 12 standard chromatic pitch class names (Sharps).
  static const List<String> chromaticNoteNames = [
    'C',
    'C♯',
    'D',
    'D♯',
    'E',
    'F',
    'F♯',
    'G',
    'G♯',
    'A',
    'A♯',
    'B',
  ];

  /// 12 standard chromatic pitch class names with flats.
  static const List<String> chromaticFlats = [
    'C',
    'D♭',
    'D',
    'E♭',
    'E',
    'F',
    'G♭',
    'G',
    'A♭',
    'A',
    'B♭',
    'B',
  ];

  /// Returns note name formatted with preferred accidental notation (# vs ♭).
  String formattedNoteName({bool preferSharps = true}) {
    final pitchClass = midiNote % 12;
    return preferSharps
        ? chromaticNoteNames[pitchClass]
        : chromaticFlats[pitchClass];
  }

  /// Creates a [GuitarString] from a MIDI note number (e.g. 40 -> E2, 60 -> C4).
  factory GuitarString.fromMidi({
    required int stringNumber,
    required int midiNote,
    String? noteName,
  }) {
    final note = noteName ?? chromaticNoteNames[midiNote % 12];
    final octave = (midiNote ~/ 12) - 1;
    return GuitarString(
      stringNumber: stringNumber,
      noteName: note,
      octave: octave,
      midiNote: midiNote,
    );
  }

  /// Returns a copy of this string transposed to a new [newMidiNote].
  GuitarString withMidiNote(int newMidiNote) {
    return GuitarString.fromMidi(
      stringNumber: stringNumber,
      midiNote: newMidiNote,
    );
  }

  /// Serializes this string to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'stringNumber': stringNumber,
    'noteName': noteName,
    'octave': octave,
    'midiNote': midiNote,
  };

  /// Deserializes a string from a JSON map.
  factory GuitarString.fromJson(Map<String, dynamic> json) {
    return GuitarString(
      stringNumber: json['stringNumber'] as int,
      noteName: json['noteName'] as String,
      octave: json['octave'] as int,
      midiNote: json['midiNote'] as int,
    );
  }

  @override
  String toString() => fullLabel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuitarString &&
          runtimeType == other.runtimeType &&
          stringNumber == other.stringNumber &&
          noteName == other.noteName &&
          octave == other.octave &&
          midiNote == other.midiNote;

  @override
  int get hashCode =>
      stringNumber.hashCode ^
      noteName.hashCode ^
      octave.hashCode ^
      midiNote.hashCode;
}
