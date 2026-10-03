import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

void main() {
  group('TuningPreset.transpose', () {
    test('transposing by 0 returns original preset without changes', () {
      final standard = TuningPreset.standard;
      final transposed = standard.transpose(0);

      expect(transposed, equals(standard));
      expect(transposed.notesSummary, 'E A D G B E');
    });

    test('transposing Standard down 1 half-step yields Eb standard', () {
      final standard = TuningPreset.standard;
      final transposed = standard.transpose(-1);

      expect(transposed.strings.length, equals(6));
      expect(transposed.notesSummary, 'E♭ A♭ D♭ G♭ B♭ E♭');
      // String 6 (E2 = 40 -> Eb2 = 39)
      expect(transposed.strings[0].midiNote, equals(39));
      expect(transposed.strings[0].noteName, equals('E♭'));
      expect(transposed.strings[0].octave, equals(2));
      // String 1 (E4 = 64 -> Eb4 = 63)
      expect(transposed.strings[5].midiNote, equals(63));
      expect(transposed.strings[5].noteName, equals('E♭'));
      expect(transposed.strings[5].octave, equals(4));
    });

    test('transposing Standard down 2 half-steps yields D standard', () {
      final standard = TuningPreset.standard;
      final transposed = standard.transpose(-2);

      expect(transposed.notesSummary, 'D G C F A D');
      expect(transposed.strings[0].midiNote, equals(38)); // D2
      expect(transposed.strings[0].noteName, equals('D'));
    });

    test('transposing Standard up 1 half-step yields F / Capo 1', () {
      final standard = TuningPreset.standard;
      final transposed = standard.transpose(1);

      expect(transposed.strings[0].midiNote, equals(41)); // F2
      expect(transposed.strings[0].noteName, equals('F'));
      expect(transposed.strings[5].midiNote, equals(65)); // F4
      expect(transposed.strings[5].noteName, equals('F'));
    });

    test('transposing Drop D down 1 half-step yields Drop Db / Drop C#', () {
      final dropD = TuningPreset.dropD;
      final transposed = dropD.transpose(-1);

      expect(transposed.strings[0].midiNote, equals(37)); // Db2
      expect(transposed.strings[0].noteName, equals('D♭'));
      expect(transposed.notesSummary, 'D♭ A♭ D♭ G♭ B♭ E♭');
    });
  });
}
