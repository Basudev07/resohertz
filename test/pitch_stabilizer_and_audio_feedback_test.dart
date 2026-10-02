import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/audio/audio_feedback_service.dart';
import 'package:resohertz/tuner/guitar_pick_indicator.dart';
import 'package:resohertz/tuner/pitch_stabilizer.dart';
import 'package:resohertz/tuner/tuning_result.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Asset Verification - success.mp3', () {
    test('success.mp3 asset file exists and has non-empty audio data', () {
      final file = File('lib/audio/success.mp3');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Expected lib/audio/success.mp3 to exist',
      );
      final bytes = file.readAsBytesSync();
      expect(
        bytes.length,
        greaterThan(1000),
        reason: 'Expected success.mp3 to contain valid audio data',
      );
    });
  });

  group('AudioFeedbackService', () {
    test(
      'invokes playInTuneSound on com.resohertz/audio_feedback channel',
      () async {
        int invokeCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(AudioFeedbackService.channelName),
              (MethodCall call) async {
                if (call.method == 'playInTuneSound') {
                  invokeCount++;
                  return 1200;
                }
                return null;
              },
            );

        final service = AudioFeedbackService();
        await service.playInTuneSound();

        expect(invokeCount, equals(1));
        expect(service.isPlaying, isTrue);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(AudioFeedbackService.channelName),
              null,
            );
      },
    );

    test(
      'throttles rapid calls within minInterval to prevent resonance',
      () async {
        int invokeCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(AudioFeedbackService.channelName),
              (MethodCall call) async {
                if (call.method == 'playInTuneSound') {
                  invokeCount++;
                  return 1200;
                }
                return null;
              },
            );

        final service = AudioFeedbackService();
        await service.playInTuneSound();
        expect(invokeCount, equals(1));

        // Immediate second call should be ignored by cooldown protection
        await service.playInTuneSound();
        expect(invokeCount, equals(1));

        service.reset();
        expect(service.isPlaying, isFalse);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(AudioFeedbackService.channelName),
              null,
            );
      },
    );

    test(
      'gracefully catches platform channel errors without throwing',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(AudioFeedbackService.channelName),
              (MethodCall call) async {
                throw PlatformException(code: 'AUDIO_ERROR', message: 'Failed');
              },
            );

        final service = AudioFeedbackService();
        await service.playInTuneSound();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(AudioFeedbackService.channelName),
              null,
            );
      },
    );
  });

  group('PitchStabilizer', () {
    final string5 = TuningPreset.standard.strings[4]; // A2 (String 5)
    final string6 = TuningPreset.standard.strings[5]; // E2 (String 6)

    test('returns 0.0 when unpitched', () {
      final stabilizer = PitchStabilizer();
      expect(stabilizer.update(const TuningResult.unpitched()), equals(0.0));
      expect(stabilizer.hasValue, isFalse);
    });

    test('snaps immediately to raw cents on initial pitched frame', () {
      final stabilizer = PitchStabilizer();
      final tuning = TuningResult(
        targetString: string5,
        targetFrequency: 110.0,
        detectedFrequency: 109.2,
        centsDifference: -12.4,
        status: TuningStatus.flat,
        confidence: 0.95,
        isPitched: true,
      );

      final result = stabilizer.update(tuning);
      expect(result, closeTo(-12.4, 0.001));
      expect(stabilizer.hasValue, isTrue);
      expect(stabilizer.smoothedCents, closeTo(-12.4, 0.001));
    });

    test('smooths small jitter fluctuations on subsequent frames', () {
      final stabilizer = PitchStabilizer();

      // Frame 1: baseline at -10.0 cents
      stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 109.3,
          centsDifference: -10.0,
          status: TuningStatus.flat,
          confidence: 0.95,
          isPitched: true,
        ),
      );

      // Frame 2: noise jitter jumping to -11.5 cents (+1.5 delta)
      final smoothed = stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 109.2,
          centsDifference: -11.5,
          status: TuningStatus.flat,
          confidence: 0.95,
          isPitched: true,
        ),
      );

      // With alpha ~0.20, smoothed value should dampen the jump (approx -10.3 cents)
      expect(smoothed, lessThan(-10.0));
      expect(smoothed, greaterThan(-11.0));
      expect(smoothed, closeTo(-10.3, 0.15));
    });

    test('responds quickly to genuine large pitch changes (> 7 cents)', () {
      final stabilizer = PitchStabilizer();

      // Frame 1: baseline at -10.0 cents
      stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 109.3,
          centsDifference: -10.0,
          status: TuningStatus.flat,
          confidence: 0.95,
          isPitched: true,
        ),
      );

      // Frame 2: user turns peg briskly from -10.0 to +5.0 cents (delta = 15.0)
      final smoothed = stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 110.3,
          centsDifference: 5.0,
          status: TuningStatus.sharp,
          confidence: 0.95,
          isPitched: true,
        ),
      );

      // Progressive smoothing (alpha 0.50) glides smoothly across large jumps
      expect(smoothed, greaterThan(-5.0));
      expect(smoothed, closeTo(-2.5, 0.2));
    });

    test('snaps immediately without gliding when target string changes', () {
      final stabilizer = PitchStabilizer();

      // Frame 1 on String 5 at -20.0 cents
      stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 108.7,
          centsDifference: -20.0,
          status: TuningStatus.flat,
          confidence: 0.95,
          isPitched: true,
        ),
      );

      // Frame 2 user plucks String 6 at +15.0 cents
      final smoothed = stabilizer.update(
        TuningResult(
          targetString: string6,
          targetFrequency: 82.41,
          detectedFrequency: 83.1,
          centsDifference: 15.0,
          status: TuningStatus.sharp,
          confidence: 0.95,
          isPitched: true,
        ),
      );

      // Must snap immediately to +15.0 cents, NOT interpolate from -20
      expect(smoothed, closeTo(15.0, 0.001));
    });

    test(
      'locks dead-center (0.0 cents) when status is inTune and close to 0',
      () {
        final stabilizer = PitchStabilizer();

        // Note is inTune with small remaining discrepancy of 0.4 cents
        final smoothed = stabilizer.update(
          TuningResult(
            targetString: string5,
            targetFrequency: 110.0,
            detectedFrequency: 110.02,
            centsDifference: 0.4,
            status: TuningStatus.inTune,
            confidence: 0.98,
            isPitched: true,
          ),
        );

        // Should gently lock right at 0.0
        expect(smoothed, equals(0.0));
      },
    );

    test('holds last reliable reading during string decay for holdDuration', () {
      final stabilizer = PitchStabilizer(
        holdDuration: const Duration(milliseconds: 300),
      );
      final startTime = DateTime(2026, 1, 1, 12, 0, 0);

      // Frame 1: pitched detection at -5.0 cents
      stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 109.68,
          centsDifference: -5.0,
          status: TuningStatus.flat,
          confidence: 0.95,
          isPitched: true,
        ),
        timestamp: startTime,
      );
      expect(stabilizer.hasValue, isTrue);
      expect(stabilizer.isHolding, isFalse);
      expect(stabilizer.smoothedCents, closeTo(-5.0, 0.01));

      // Frame 2: 100ms later, signal fades into weak unpitched
      final heldCents = stabilizer.update(
        const TuningResult.unpitched(),
        timestamp: startTime.add(const Duration(milliseconds: 100)),
      );
      expect(stabilizer.hasValue, isTrue);
      expect(stabilizer.isHolding, isTrue);
      expect(heldCents, closeTo(-5.0, 0.01));
      expect(stabilizer.lastReliableResult?.targetString?.stringNumber, equals(5));

      // Frame 3: 200ms later, still in hold window
      final stillHeldCents = stabilizer.update(
        const TuningResult.unpitched(),
        timestamp: startTime.add(const Duration(milliseconds: 200)),
      );
      expect(stabilizer.hasValue, isTrue);
      expect(stabilizer.isHolding, isTrue);
      expect(stillHeldCents, closeTo(-5.0, 0.01));

      // Frame 4: 350ms later, hold expires -> returns to 0.0 and unpitched
      final expiredCents = stabilizer.update(
        const TuningResult.unpitched(),
        timestamp: startTime.add(const Duration(milliseconds: 350)),
      );
      expect(expiredCents, equals(0.0));
      expect(stabilizer.hasValue, isFalse);
      expect(stabilizer.isHolding, isFalse);
    });

    test('continues tracking peg adjustments when pitched frame arrives during hold', () {
      final stabilizer = PitchStabilizer(
        holdDuration: const Duration(milliseconds: 300),
      );
      final startTime = DateTime(2026, 1, 1, 12, 0, 0);

      // Pitched frame
      stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 109.68,
          centsDifference: -5.0,
          status: TuningStatus.flat,
          confidence: 0.95,
          isPitched: true,
        ),
        timestamp: startTime,
      );

      // Unpitched frame (enters hold)
      stabilizer.update(
        const TuningResult.unpitched(),
        timestamp: startTime.add(const Duration(milliseconds: 100)),
      );
      expect(stabilizer.isHolding, isTrue);

      // User turned peg sharp: new pitched frame arrives at +2.0 cents (150ms after start)
      final updated = stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 110.13,
          centsDifference: 2.0,
          status: TuningStatus.inTune,
          confidence: 0.95,
          isPitched: true,
        ),
        timestamp: startTime.add(const Duration(milliseconds: 150)),
      );

      expect(stabilizer.isHolding, isFalse);
      expect(stabilizer.hasValue, isTrue);
      // Smoothed value tracks from -5.0 towards 2.0
      expect(updated, greaterThan(-5.0));
    });

    test('reset clears internal state', () {
      final stabilizer = PitchStabilizer();

      stabilizer.update(
        TuningResult(
          targetString: string5,
          targetFrequency: 110.0,
          detectedFrequency: 110.9,
          centsDifference: 14.0,
          status: TuningStatus.sharp,
          confidence: 0.95,
          isPitched: true,
        ),
      );
      expect(stabilizer.hasValue, isTrue);

      stabilizer.reset();
      expect(stabilizer.hasValue, isFalse);
      expect(stabilizer.smoothedCents, equals(0.0));
    });
  });

  group('HorizontalTuningScale & GuitarPickMarker Widget', () {
    testWidgets(
      'renders horizontal tuning scale labels and guitar pick marker',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: HorizontalTuningScale(
                stabilizedCents: 0.0,
                isPitched: true,
                status: TuningStatus.inTune,
                statusColor: Color(0xFFDCF4A2),
                isDark: true,
              ),
            ),
          ),
        );

        // Verify scale labels
        expect(find.text('-50¢'), findsOneWidget);
        expect(find.text('0¢ (In Tune)'), findsOneWidget);
        expect(find.text('+50¢'), findsOneWidget);

        // Verify guitar pick marker
        expect(find.byKey(const Key('guitar_pick_marker')), findsOneWidget);
      },
    );

    testWidgets('guitar pick marker animates smoothly based on cents', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HorizontalTuningScale(
              stabilizedCents: -25.0,
              isPitched: true,
              status: TuningStatus.flat,
              statusColor: Color(0xFFFFD54F),
              isDark: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guitar_pick_marker')), findsOneWidget);
    });
  });

  group('In-Tune Audio Feedback State Machine', () {
    test(
      'triggers sound once on entering in-tune, not repeatedly while in-tune',
      () {
        int audioTriggerCount = 0;
        TuningStatus previousStatus = TuningStatus.unpitched;

        void processFrame(TuningStatus currentStatus) {
          if (currentStatus == TuningStatus.inTune &&
              previousStatus != TuningStatus.inTune) {
            audioTriggerCount++;
          }
          previousStatus = currentStatus;
        }

        // 1. Unpitched -> Flat -> Flat (tuning note)
        processFrame(TuningStatus.flat);
        expect(audioTriggerCount, equals(0));

        processFrame(TuningStatus.flat);
        expect(audioTriggerCount, equals(0));

        // 2. Enters In-Tune for the first time -> triggers audio feedback!
        processFrame(TuningStatus.inTune);
        expect(audioTriggerCount, equals(1));

        // 3. Remains In-Tune for next 10 frames -> must NOT trigger again!
        for (int i = 0; i < 10; i++) {
          processFrame(TuningStatus.inTune);
        }
        expect(audioTriggerCount, equals(1));

        // 4. Pitch fluctuates slightly flat -> leaves in-tune
        processFrame(TuningStatus.flat);
        expect(audioTriggerCount, equals(1));

        // 5. User adjusts peg and re-enters In-Tune -> triggers audio feedback once again!
        processFrame(TuningStatus.inTune);
        expect(audioTriggerCount, equals(2));

        // 6. Continues in tune -> no repeated trigger
        processFrame(TuningStatus.inTune);
        expect(audioTriggerCount, equals(2));
      },
    );
  });

  group('TuningResult - Hysteresis & In-Tune Stability', () {
    test('entering inTune requires cents within strict tolerance (<= 3.0)', () {
      // 3.2 cents while previous status was flat/sharp -> remains sharp
      expect(
        TuningResult.determineStatusWithHysteresis(
          3.2,
          previousStatus: TuningStatus.sharp,
          toleranceCents: 3.0,
          hysteresisCents: 1.0,
        ),
        equals(TuningStatus.sharp),
      );

      // 2.9 cents -> enters inTune
      expect(
        TuningResult.determineStatusWithHysteresis(
          2.9,
          previousStatus: TuningStatus.sharp,
          toleranceCents: 3.0,
          hysteresisCents: 1.0,
        ),
        equals(TuningStatus.inTune),
      );
    });

    test('exiting inTune requires exceeding tolerance + hysteresis (> 4.0)', () {
      // Micro-fluctuation to 3.5 cents while already inTune -> stays inTune!
      expect(
        TuningResult.determineStatusWithHysteresis(
          3.5,
          previousStatus: TuningStatus.inTune,
          toleranceCents: 3.0,
          hysteresisCents: 1.0,
        ),
        equals(TuningStatus.inTune),
      );

      // Micro-fluctuation to -3.8 cents while inTune -> stays inTune!
      expect(
        TuningResult.determineStatusWithHysteresis(
          -3.8,
          previousStatus: TuningStatus.inTune,
          toleranceCents: 3.0,
          hysteresisCents: 1.0,
        ),
        equals(TuningStatus.inTune),
      );

      // Genuine peg turn to +4.3 cents -> cleanly exits inTune to sharp!
      expect(
        TuningResult.determineStatusWithHysteresis(
          4.3,
          previousStatus: TuningStatus.inTune,
          toleranceCents: 3.0,
          hysteresisCents: 1.0,
        ),
        equals(TuningStatus.sharp),
      );
    });
  });
}
