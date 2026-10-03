import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/pitch/pitch_result.dart';
import 'package:resohertz/tuner/tuner_engine.dart';
import 'package:resohertz/tuner/tuning_result.dart';
import 'package:resohertz/tuning/reference_frequency.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

void main() {
  group('Standard Guitar Tuning - Equal Temperament Target Frequencies', () {
    const preset = TuningPreset.standard;

    test('verifies standard A4=440 Hz theoretical string frequencies', () {
      final s6 = preset.strings.firstWhere((s) => s.stringNumber == 6); // E2
      final s5 = preset.strings.firstWhere((s) => s.stringNumber == 5); // A2
      final s4 = preset.strings.firstWhere((s) => s.stringNumber == 4); // D3
      final s3 = preset.strings.firstWhere((s) => s.stringNumber == 3); // G3
      final s2 = preset.strings.firstWhere((s) => s.stringNumber == 2); // B3
      final s1 = preset.strings.firstWhere((s) => s.stringNumber == 1); // E4

      expect(s6.displayName, 'E2');
      expect(s6.frequencyAt(440.0), closeTo(82.407, 0.001));

      expect(s5.displayName, 'A2');
      expect(s5.frequencyAt(440.0), closeTo(110.000, 0.001));

      expect(s4.displayName, 'D3');
      expect(s4.frequencyAt(440.0), closeTo(146.832, 0.001));

      expect(s3.displayName, 'G3');
      expect(s3.frequencyAt(440.0), closeTo(195.998, 0.001));

      expect(s2.displayName, 'B3');
      expect(s2.frequencyAt(440.0), closeTo(246.942, 0.001));

      expect(s1.displayName, 'E4');
      expect(s1.frequencyAt(440.0), closeTo(329.628, 0.001));
    });

    test(
      'recalculates string frequencies correctly for A4=432 Hz reference',
      () {
        final s5 = preset.strings.firstWhere((s) => s.stringNumber == 5); // A2
        expect(s5.frequencyAt(432.0), closeTo(108.000, 0.001));

        final s6 = preset.strings.firstWhere((s) => s.stringNumber == 6); // E2
        expect(s6.frequencyAt(432.0), closeTo(82.407 * (432.0 / 440.0), 0.001));
      },
    );
  });

  group('TuningPreset - Closest String Matching', () {
    const preset = TuningPreset.standard;

    test(
      'identifies closest string for frequencies across the guitar register',
      () {
        expect(preset.findClosestString(83.0).displayName, 'E2'); // String 6
        expect(preset.findClosestString(109.0).displayName, 'A2'); // String 5
        expect(preset.findClosestString(148.0).displayName, 'D3'); // String 4
        expect(preset.findClosestString(194.0).displayName, 'G3'); // String 3
        expect(preset.findClosestString(250.0).displayName, 'B3'); // String 2
        expect(preset.findClosestString(328.0).displayName, 'E4'); // String 1
      },
    );
  });

  group('TuningResult - Cents calculation and status evaluation', () {
    test('exact match yields 0 cents and inTune status', () {
      final cents = TuningResult.calculateCents(110.0, 110.0);
      expect(cents, 0.0);
      expect(TuningResult.determineStatus(cents), TuningStatus.inTune);
    });

    test('flat pitch yields negative cents and flat status', () {
      final cents = TuningResult.calculateCents(108.5, 110.0);
      expect(cents, closeTo(-23.77, 0.01));
      expect(TuningResult.determineStatus(cents), TuningStatus.flat);
    });

    test('sharp pitch yields positive cents and sharp status', () {
      final cents = TuningResult.calculateCents(111.5, 110.0);
      expect(cents, closeTo(23.44, 0.01));
      expect(TuningResult.determineStatus(cents), TuningStatus.sharp);
    });

    test('tolerance window (±3 cents) classifies as inTune', () {
      final centsWithinPos = TuningResult.calculateCents(110.15, 110.0);
      expect(centsWithinPos, closeTo(2.36, 0.01));
      expect(
        TuningResult.determineStatus(centsWithinPos, toleranceCents: 3.0),
        TuningStatus.inTune,
      );

      final centsWithinNeg = TuningResult.calculateCents(109.85, 110.0);
      expect(centsWithinNeg, closeTo(-2.36, 0.01));
      expect(
        TuningResult.determineStatus(centsWithinNeg, toleranceCents: 3.0),
        TuningStatus.inTune,
      );
    });
  });

  group('TunerEngine - Full Evaluation Pipeline', () {
    const engine = TunerEngine();

    test('evaluates in-tune A2 guitar pluck within ±1.0 cent', () {
      const pitch = PitchResult(
        frequency: 110.03,
        confidence: 0.96,
        isPitched: true,
      );
      final result = engine.evaluate(pitchResult: pitch);

      expect(result.isPitched, isTrue);
      expect(result.targetString?.displayName, 'A2');
      expect(result.targetFrequency, closeTo(110.0, 0.001));
      expect(result.detectedFrequency, 110.03);
      expect(result.centsDifference, closeTo(0.47, 0.05));
      expect(result.status, TuningStatus.inTune);
    });

    test('evaluates 110.1 Hz (1.57 cents) as sharp under ±1.0 cent precision threshold', () {
      const pitch = PitchResult(
        frequency: 110.1,
        confidence: 0.96,
        isPitched: true,
      );
      final result = engine.evaluate(pitchResult: pitch);

      expect(result.isPitched, isTrue);
      expect(result.centsDifference, closeTo(1.57, 0.05));
      expect(result.status, TuningStatus.sharp);
    });

    test('evaluates flat E2 guitar pluck', () {
      const pitch = PitchResult(
        frequency: 80.5,
        confidence: 0.94,
        isPitched: true,
      );
      final result = engine.evaluate(pitchResult: pitch);

      expect(result.isPitched, isTrue);
      expect(result.targetString?.displayName, 'E2');
      expect(result.status, TuningStatus.flat);
      expect(result.centsDifference, lessThan(-3.0));
    });

    test('evaluates sharp E4 guitar pluck', () {
      const pitch = PitchResult(
        frequency: 334.0,
        confidence: 0.95,
        isPitched: true,
      );
      final result = engine.evaluate(pitchResult: pitch);

      expect(result.isPitched, isTrue);
      expect(result.targetString?.displayName, 'E4');
      expect(result.status, TuningStatus.sharp);
      expect(result.centsDifference, greaterThan(3.0));
    });

    test('evaluates unpitched input as unpitched result', () {
      final result = engine.evaluate(
        pitchResult: const PitchResult.unpitched(),
      );
      expect(result.isPitched, isFalse);
      expect(result.status, TuningStatus.unpitched);
      expect(result.targetString, isNull);
    });
  });

  group('ReferenceFrequency Model & Presets', () {
    test('contains correct standard, verdi, and orchestral constants', () {
      expect(ReferenceFrequency.standard, 440.0);
      expect(ReferenceFrequency.verdi, 432.0);
      expect(ReferenceFrequency.orchestral, 442.0);
      expect(ReferenceFrequency.commonPresets, [432.0, 440.0, 442.0]);
    });

    test('clamps custom frequencies to historical range [415, 466]', () {
      expect(ReferenceFrequency.clamp(400.0), 415.0);
      expect(ReferenceFrequency.clamp(435.5), 435.5);
      expect(ReferenceFrequency.clamp(500.0), 466.0);
    });

    test('formats frequency values cleanly', () {
      expect(ReferenceFrequency.format(440.0), '440 Hz');
      expect(ReferenceFrequency.format(432.5), '432.5 Hz');
    });
  });

  group('TunerEngine - Reference Frequency Recalculation', () {
    const preset = TuningPreset.standard;

    test('verifies Verdi 432 Hz tuning: 108.0 Hz A2 is 0.0 cents in-tune', () {
      const engine432 = TunerEngine(referenceA4: 432.0);
      const pitch108 = PitchResult(
        frequency: 108.0,
        confidence: 0.98,
        isPitched: true,
      );
      final result = engine432.evaluate(pitchResult: pitch108, preset: preset);

      expect(result.targetString?.displayName, 'A2');
      expect(result.targetFrequency, 108.0);
      expect(result.centsDifference, closeTo(0.0, 0.001));
      expect(result.status, TuningStatus.inTune);
    });

    test('verifies 108.0 Hz on standard 440 Hz is flat (-31.77 cents)', () {
      const engine440 = TunerEngine(referenceA4: 440.0);
      const pitch108 = PitchResult(
        frequency: 108.0,
        confidence: 0.98,
        isPitched: true,
      );
      final result = engine440.evaluate(pitchResult: pitch108, preset: preset);

      expect(result.targetString?.displayName, 'A2');
      expect(result.targetFrequency, 110.0);
      expect(result.centsDifference, closeTo(-31.77, 0.05));
      expect(result.status, TuningStatus.flat);
    });

    test(
      'verifies Orchestral 442 Hz tuning: 110.5 Hz A2 is 0.0 cents in-tune',
      () {
        const engine442 = TunerEngine(referenceA4: 442.0);
        const pitch110_5 = PitchResult(
          frequency: 110.5,
          confidence: 0.98,
          isPitched: true,
        );
        final result = engine442.evaluate(
          pitchResult: pitch110_5,
          preset: preset,
        );

        expect(result.targetString?.displayName, 'A2');
        expect(result.targetFrequency, 110.5);
        expect(result.centsDifference, closeTo(0.0, 0.001));
        expect(result.status, TuningStatus.inTune);
      },
    );

    test(
      'verifies custom reference frequency (436 Hz): 109.0 Hz A2 is 0.0 cents in-tune',
      () {
        const engine = TunerEngine(referenceA4: 440.0);
        const pitch109 = PitchResult(
          frequency: 109.0,
          confidence: 0.98,
          isPitched: true,
        );
        final result = engine.evaluate(
          pitchResult: pitch109,
          preset: preset,
          referenceA4: 436.0,
        );

        expect(result.targetString?.displayName, 'A2');
        expect(result.targetFrequency, 109.0);
        expect(result.centsDifference, closeTo(0.0, 0.001));
        expect(result.status, TuningStatus.inTune);
      },
    );

    test('copyWith properly preserves or updates referenceA4', () {
      const engine = TunerEngine(referenceA4: 440.0, inTuneToleranceCents: 2.5);
      final copied = engine.copyWith(referenceA4: 432.0);

      expect(copied.referenceA4, 432.0);
      expect(copied.inTuneToleranceCents, 2.5);
    });
  });

  group('TuningPreset - Alternate Tunings', () {
    test('contains all 8 standard and alternate presets', () {
      expect(TuningPreset.allPresets.length, 8);
      expect(TuningPreset.allPresets.map((p) => p.id), [
        'standard',
        'drop_d',
        'half_step_down',
        'd_standard',
        'drop_c',
        'dadgad',
        'open_d',
        'open_g',
      ]);
    });

    test('Drop D has correct D2 String 6 frequency (~73.42 Hz)', () {
      final dropD = TuningPreset.dropD;
      expect(dropD.notesSummary, 'D A D G B E');
      final s6 = dropD.strings.firstWhere((s) => s.stringNumber == 6);
      expect(s6.displayName, 'D2');
      expect(s6.frequencyAt(440.0), closeTo(73.416, 0.001));
    });

    test('Half-Step Down has correct E♭2 String 6 and E♭4 String 1', () {
      final eb = TuningPreset.halfStepDown;
      expect(eb.notesSummary, 'E♭ A♭ D♭ G♭ B♭ E♭');
      final s6 = eb.strings.firstWhere((s) => s.stringNumber == 6);
      final s1 = eb.strings.firstWhere((s) => s.stringNumber == 1);
      expect(s6.displayName, 'E♭2');
      expect(s6.frequencyAt(440.0), closeTo(77.782, 0.001));
      expect(s1.displayName, 'E♭4');
      expect(s1.frequencyAt(440.0), closeTo(311.127, 0.001));
    });

    test('D Standard has correct D2 String 6 and D4 String 1', () {
      final dStd = TuningPreset.dStandard;
      expect(dStd.notesSummary, 'D G C F A D');
      final s6 = dStd.strings.firstWhere((s) => s.stringNumber == 6);
      final s1 = dStd.strings.firstWhere((s) => s.stringNumber == 1);
      expect(s6.displayName, 'D2');
      expect(s1.displayName, 'D4');
      expect(s1.frequencyAt(440.0), closeTo(293.665, 0.001));
    });

    test('Drop C has correct C2 String 6 frequency (~65.41 Hz)', () {
      final dropC = TuningPreset.dropC;
      expect(dropC.notesSummary, 'C G C F A D');
      final s6 = dropC.strings.firstWhere((s) => s.stringNumber == 6);
      expect(s6.displayName, 'C2');
      expect(s6.frequencyAt(440.0), closeTo(65.406, 0.001));
    });

    test('DADGAD has correct D2 String 6 and D4 String 1', () {
      final dadgad = TuningPreset.dadgad;
      expect(dadgad.notesSummary, 'D A D G A D');
      final s2 = dadgad.strings.firstWhere((s) => s.stringNumber == 2);
      expect(s2.displayName, 'A3');
      expect(s2.frequencyAt(440.0), closeTo(220.000, 0.001));
    });

    test('Open D has correct F♯3 String 3', () {
      final openD = TuningPreset.openD;
      expect(openD.notesSummary, 'D A D F♯ A D');
      final s3 = openD.strings.firstWhere((s) => s.stringNumber == 3);
      expect(s3.displayName, 'F♯3');
      expect(s3.frequencyAt(440.0), closeTo(184.997, 0.001));
    });

    test('Open G has correct B3 String 2 and D4 String 1', () {
      final openG = TuningPreset.openG;
      expect(openG.notesSummary, 'D G D G B D');
      final s2 = openG.strings.firstWhere((s) => s.stringNumber == 2);
      expect(s2.displayName, 'B3');
      expect(s2.frequencyAt(440.0), closeTo(246.942, 0.001));
    });

    test(
      'TuningPreset.byId returns correct preset or defaults to standard',
      () {
        expect(TuningPreset.byId('drop_d'), TuningPreset.dropD);
        expect(TuningPreset.byId('drop_c'), TuningPreset.dropC);
        expect(TuningPreset.byId('unknown_xyz'), TuningPreset.standard);
      },
    );

    test('TunerEngine evaluates Drop D low D2 pluck as in-tune String 6', () {
      const engine = TunerEngine();
      const pitchD2 = PitchResult(
        frequency: 73.45,
        confidence: 0.96,
        isPitched: true,
      );
      final result = engine.evaluate(
        pitchResult: pitchD2,
        preset: TuningPreset.dropD,
      );

      expect(result.targetString?.displayName, 'D2');
      expect(result.targetString?.stringNumber, 6);
      expect(result.targetFrequency, closeTo(73.416, 0.001));
      expect(result.status, TuningStatus.inTune);
    });

    test('TunerEngine evaluates Drop C low C2 pluck as in-tune String 6', () {
      const engine = TunerEngine();
      const pitchC2 = PitchResult(
        frequency: 65.41,
        confidence: 0.95,
        isPitched: true,
      );
      final result = engine.evaluate(
        pitchResult: pitchC2,
        preset: TuningPreset.dropC,
      );

      expect(result.targetString?.displayName, 'C2');
      expect(result.targetString?.stringNumber, 6);
      expect(result.targetFrequency, closeTo(65.406, 0.001));
      expect(result.status, TuningStatus.inTune);
    });
  });
}
