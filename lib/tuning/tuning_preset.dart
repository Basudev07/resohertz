import 'dart:math' as math;
import 'package:resohertz/tuning/guitar_string.dart';

/// Represents a musical tuning preset composed of ordered guitar strings.
class TuningPreset {
  final String id;
  final String name;
  final List<GuitarString> strings;
  final bool isCustom;

  const TuningPreset({
    required this.id,
    required this.name,
    required this.strings,
    this.isCustom = false,
  });

  /// Formatted notes from lowest pitch (string 6) to highest pitch (string 1),
  /// e.g. "E A D G B E" or "D A D G B E".
  String get notesSummary => strings.map((s) => s.noteName).join(' ');

  /// Full description, e.g. "Standard (E A D G B E)".
  String get fullTitle => '$name ($notesSummary)';

  /// Standard Guitar Tuning: E2 - A2 - D3 - G3 - B3 - E4
  static const TuningPreset standard = TuningPreset(
    id: 'standard',
    name: 'Standard Tuning',
    strings: [
      GuitarString(stringNumber: 6, noteName: 'E', octave: 2, midiNote: 40),
      GuitarString(stringNumber: 5, noteName: 'A', octave: 2, midiNote: 45),
      GuitarString(stringNumber: 4, noteName: 'D', octave: 3, midiNote: 50),
      GuitarString(stringNumber: 3, noteName: 'G', octave: 3, midiNote: 55),
      GuitarString(stringNumber: 2, noteName: 'B', octave: 3, midiNote: 59),
      GuitarString(stringNumber: 1, noteName: 'E', octave: 4, midiNote: 64),
    ],
  );

  /// Drop D Tuning: D2 - A2 - D3 - G3 - B3 - E4
  static const TuningPreset dropD = TuningPreset(
    id: 'drop_d',
    name: 'Drop D',
    strings: [
      GuitarString(stringNumber: 6, noteName: 'D', octave: 2, midiNote: 38),
      GuitarString(stringNumber: 5, noteName: 'A', octave: 2, midiNote: 45),
      GuitarString(stringNumber: 4, noteName: 'D', octave: 3, midiNote: 50),
      GuitarString(stringNumber: 3, noteName: 'G', octave: 3, midiNote: 55),
      GuitarString(stringNumber: 2, noteName: 'B', octave: 3, midiNote: 59),
      GuitarString(stringNumber: 1, noteName: 'E', octave: 4, midiNote: 64),
    ],
  );

  /// Half-Step Down (E♭ Standard): E♭2 - A♭2 - D♭3 - G♭3 - B♭3 - E♭4
  static const TuningPreset halfStepDown = TuningPreset(
    id: 'half_step_down',
    name: 'Half-Step Down',
    strings: [
      GuitarString(stringNumber: 6, noteName: 'E♭', octave: 2, midiNote: 39),
      GuitarString(stringNumber: 5, noteName: 'A♭', octave: 2, midiNote: 44),
      GuitarString(stringNumber: 4, noteName: 'D♭', octave: 3, midiNote: 49),
      GuitarString(stringNumber: 3, noteName: 'G♭', octave: 3, midiNote: 54),
      GuitarString(stringNumber: 2, noteName: 'B♭', octave: 3, midiNote: 58),
      GuitarString(stringNumber: 1, noteName: 'E♭', octave: 4, midiNote: 63),
    ],
  );

  /// D Standard (Full Step Down): D2 - G2 - C3 - F3 - A3 - D4
  static const TuningPreset dStandard = TuningPreset(
    id: 'd_standard',
    name: 'D Standard',
    strings: [
      GuitarString(stringNumber: 6, noteName: 'D', octave: 2, midiNote: 38),
      GuitarString(stringNumber: 5, noteName: 'G', octave: 2, midiNote: 43),
      GuitarString(stringNumber: 4, noteName: 'C', octave: 3, midiNote: 48),
      GuitarString(stringNumber: 3, noteName: 'F', octave: 3, midiNote: 53),
      GuitarString(stringNumber: 2, noteName: 'A', octave: 3, midiNote: 57),
      GuitarString(stringNumber: 1, noteName: 'D', octave: 4, midiNote: 62),
    ],
  );

  /// Drop C Tuning: C2 - G2 - C3 - F3 - A3 - D4
  static const TuningPreset dropC = TuningPreset(
    id: 'drop_c',
    name: 'Drop C',
    strings: [
      GuitarString(stringNumber: 6, noteName: 'C', octave: 2, midiNote: 36),
      GuitarString(stringNumber: 5, noteName: 'G', octave: 2, midiNote: 43),
      GuitarString(stringNumber: 4, noteName: 'C', octave: 3, midiNote: 48),
      GuitarString(stringNumber: 3, noteName: 'F', octave: 3, midiNote: 53),
      GuitarString(stringNumber: 2, noteName: 'A', octave: 3, midiNote: 57),
      GuitarString(stringNumber: 1, noteName: 'D', octave: 4, midiNote: 62),
    ],
  );

  /// DADGAD Tuning: D2 - A2 - D3 - G3 - A3 - D4 (Celtic / Folk)
  static const TuningPreset dadgad = TuningPreset(
    id: 'dadgad',
    name: 'DADGAD',
    strings: [
      GuitarString(stringNumber: 6, noteName: 'D', octave: 2, midiNote: 38),
      GuitarString(stringNumber: 5, noteName: 'A', octave: 2, midiNote: 45),
      GuitarString(stringNumber: 4, noteName: 'D', octave: 3, midiNote: 50),
      GuitarString(stringNumber: 3, noteName: 'G', octave: 3, midiNote: 55),
      GuitarString(stringNumber: 2, noteName: 'A', octave: 3, midiNote: 57),
      GuitarString(stringNumber: 1, noteName: 'D', octave: 4, midiNote: 62),
    ],
  );

  /// Open D Tuning: D2 - A2 - D3 - F♯3 - A3 - D4
  static const TuningPreset openD = TuningPreset(
    id: 'open_d',
    name: 'Open D',
    strings: [
      GuitarString(stringNumber: 6, noteName: 'D', octave: 2, midiNote: 38),
      GuitarString(stringNumber: 5, noteName: 'A', octave: 2, midiNote: 45),
      GuitarString(stringNumber: 4, noteName: 'D', octave: 3, midiNote: 50),
      GuitarString(stringNumber: 3, noteName: 'F♯', octave: 3, midiNote: 54),
      GuitarString(stringNumber: 2, noteName: 'A', octave: 3, midiNote: 57),
      GuitarString(stringNumber: 1, noteName: 'D', octave: 4, midiNote: 62),
    ],
  );

  /// Open G Tuning: D2 - G2 - D3 - G3 - B3 - D4 (Blues / Rolling Stones)
  static const TuningPreset openG = TuningPreset(
    id: 'open_g',
    name: 'Open G',
    strings: [
      GuitarString(stringNumber: 6, noteName: 'D', octave: 2, midiNote: 38),
      GuitarString(stringNumber: 5, noteName: 'G', octave: 2, midiNote: 43),
      GuitarString(stringNumber: 4, noteName: 'D', octave: 3, midiNote: 50),
      GuitarString(stringNumber: 3, noteName: 'G', octave: 3, midiNote: 55),
      GuitarString(stringNumber: 2, noteName: 'B', octave: 3, midiNote: 59),
      GuitarString(stringNumber: 1, noteName: 'D', octave: 4, midiNote: 62),
    ],
  );

  /// All supported built-in guitar tuning presets.
  static const List<TuningPreset> builtInPresets = [
    standard,
    dropD,
    halfStepDown,
    dStandard,
    dropC,
    dadgad,
    openD,
    openG,
  ];

  /// Backward-compatible alias for built-in presets.
  static const List<TuningPreset> allPresets = builtInPresets;

  /// Finds built-in preset by [id] or returns [standard] if not found.
  static TuningPreset byId(String id) {
    return allPresets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => standard,
    );
  }

  /// Returns a copy of this preset with updated fields.
  TuningPreset copyWith({
    String? id,
    String? name,
    List<GuitarString>? strings,
    bool? isCustom,
  }) {
    return TuningPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      strings: strings ?? this.strings,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  /// Serializes this preset to a JSON map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'strings': strings.map((s) => s.toJson()).toList(),
    'isCustom': isCustom,
  };

  /// Deserializes a preset from a JSON map.
  factory TuningPreset.fromJson(Map<String, dynamic> json) {
    final rawStrings = json['strings'] as List<dynamic>? ?? [];
    final parsedStrings = rawStrings
        .map((s) => GuitarString.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
    return TuningPreset(
      id:
          json['id'] as String? ??
          'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Custom Tuning',
      strings: parsedStrings,
      isCustom: json['isCustom'] as bool? ?? true,
    );
  }

  /// Automatically finds the closest guitar string in this tuning to the given [frequency].
  /// Uses logarithmic pitch distance (|log2(f / f_target)|) so octave spacing is musically uniform.
  GuitarString findClosestString(
    double frequency, {
    double referenceA4 = 440.0,
  }) {
    if (frequency <= 0.0 || strings.isEmpty) {
      return strings.first;
    }

    GuitarString bestString = strings.first;
    double minPitchDistance = double.infinity;

    for (final string in strings) {
      final targetFreq = string.frequencyAt(referenceA4);
      final distance = (math.log(frequency / targetFreq) / math.ln2).abs();
      if (distance < minPitchDistance) {
        minPitchDistance = distance;
        bestString = string;
      }
    }

    return bestString;
  }

  /// Returns a copy of this tuning preset transposed by [semitones] half steps.
  /// Positive values transpose pitch up (+1 = half-step up, Capo 1).
  /// Negative values transpose pitch down (-1 = half-step down / E♭ standard).
  TuningPreset transpose(int semitones, {bool? preferFlats}) {
    if (semitones == 0) return this;

    final useFlats = preferFlats ?? (semitones < 0);
    final transposedStrings = strings.map((s) {
      final newMidi = s.midiNote + semitones;
      final pitchClass = (newMidi % 12 + 12) % 12;
      final note = useFlats
          ? GuitarString.chromaticFlats[pitchClass]
          : GuitarString.chromaticNoteNames[pitchClass];
      final octave = (newMidi ~/ 12) - 1;
      return GuitarString(
        stringNumber: s.stringNumber,
        noteName: note,
        octave: octave,
        midiNote: newMidi,
      );
    }).toList();

    return TuningPreset(
      id: id,
      name: name,
      strings: transposedStrings,
      isCustom: isCustom,
    );
  }

  @override
  String toString() => fullTitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TuningPreset &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
