import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/audio/audio_capture_service.dart';
import 'package:resohertz/audio/microphone_service.dart';
import 'package:resohertz/main.dart';
import 'package:resohertz/settings/app_settings.dart';
import 'package:resohertz/settings/app_settings_service.dart';
import 'package:resohertz/tuning/custom_tuning_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.resohertz/microphone';
  late MethodChannel channel;
  late MicrophoneService micService;

  setUp(() {
    channel = const MethodChannel(channelName);
    micService = MicrophoneService(channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('displays permission required when not granted', (
    WidgetTester tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'checkPermission') {
            return false;
          }
          return null;
        });

    await tester.pumpWidget(ResoHertzApp(microphoneService: micService));
    await tester.pumpAndSettle();

    expect(find.text('Microphone Permission Required'), findsOneWidget);
    expect(find.text('Grant Permission'), findsOneWidget);
  });

  testWidgets(
    'displays guitar tuner card and mic toggle when permission is granted',
    (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') {
              return true;
            }
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      await tester.pumpWidget(ResoHertzApp(microphoneService: micService));
      await tester.pumpAndSettle();

      expect(find.text('Standard Tuning (E A D G B E)'), findsOneWidget);
      expect(find.byKey(const Key('note_name_display')), findsOneWidget);
      expect(find.byKey(const Key('start_capture_button')), findsOneWidget);
      expect(find.text('TUNER OFF'), findsOneWidget);
    },
  );

  testWidgets('clicking Start/Stop listening toggles capture and updates UI', (
    WidgetTester tester,
  ) async {
    final streamController = StreamController<dynamic>.broadcast();
    final audioCaptureService = AudioCaptureService(
      testStream: streamController.stream,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'checkPermission') {
            return true;
          }
          if (methodCall.method == 'initializeMicrophone') {
            return <dynamic, dynamic>{
              'isAvailable': true,
              'sampleRate': 44100,
              'minBufferSize': 3584,
              'error': null,
            };
          }
          return null;
        });

    await tester.pumpWidget(
      ResoHertzApp(
        microphoneService: micService,
        audioCaptureService: audioCaptureService,
      ),
    );
    await tester.pumpAndSettle();

    // Initial state: not capturing, start listening button is present with slashed mic icon
    expect(find.byKey(const Key('start_capture_button')), findsOneWidget);
    expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
    expect(find.text('TUNER OFF'), findsOneWidget);

    // Tap Start Listening
    await tester.ensureVisible(find.byKey(const Key('start_capture_button')));
    await tester.tap(find.byKey(const Key('start_capture_button')));
    await tester.pump();

    // Now capturing: stop button is present, status is Listening..., mic active icon
    expect(find.byKey(const Key('stop_capture_button')), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.text('LISTENING...'), findsOneWidget);

    // Emit an audio buffer
    final buffer = ByteData(4);
    buffer.setInt16(0, 8000, Endian.little);
    buffer.setInt16(2, 8000, Endian.little);
    streamController.add(buffer.buffer.asUint8List());

    await tester.pump();

    // Tap Stop Listening
    await tester.ensureVisible(find.byKey(const Key('stop_capture_button')));
    await tester.tap(find.byKey(const Key('stop_capture_button')));
    await tester.pump();

    // Back to idle: start button is present with slashed mic icon, status is TUNER OFF
    expect(find.byKey(const Key('start_capture_button')), findsOneWidget);
    expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
    expect(find.text('TUNER OFF'), findsOneWidget);

    audioCaptureService.dispose();
    await streamController.close();
  });

  testWidgets('detects and displays pitch frequency when note is played', (
    WidgetTester tester,
  ) async {
    final streamController = StreamController<dynamic>.broadcast();
    final audioCaptureService = AudioCaptureService(
      testStream: streamController.stream,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'checkPermission') return true;
          if (methodCall.method == 'initializeMicrophone') {
            return <dynamic, dynamic>{
              'isAvailable': true,
              'sampleRate': 44100,
              'minBufferSize': 3584,
              'error': null,
            };
          }
          return null;
        });

    await tester.pumpWidget(
      ResoHertzApp(
        microphoneService: micService,
        audioCaptureService: audioCaptureService,
      ),
    );
    await tester.pumpAndSettle();

    // Start listening
    await tester.ensureVisible(find.byKey(const Key('start_capture_button')));
    await tester.tap(find.byKey(const Key('start_capture_button')));
    await tester.pump();

    expect(find.text('Listening...'), findsOneWidget);

    // Emit 110.0 Hz sine wave buffer (2048 samples)
    final buffer = ByteData(2048 * 2);
    for (int i = 0; i < 2048; i++) {
      final t = i / 44100.0;
      final sample = (math.sin(2 * math.pi * 110.0 * t) * 0.8 * 32767).round();
      buffer.setInt16(i * 2, sample, Endian.little);
    }
    streamController.add(buffer.buffer.asUint8List());

    await tester.pump();

    // Verify frequency display updates to ~110.0 Hz
    final freqFinder = find.byKey(const Key('frequency_display'));
    expect(freqFinder, findsOneWidget);
    final Text textWidget = tester.widget(freqFinder);
    expect(textWidget.data, contains('110.0 Hz'));

    // Verify confidence display
    final confFinder = find.byKey(const Key('confidence_display'));
    expect(confFinder, findsOneWidget);
    final Text confWidget = tester.widget(confFinder);
    expect(confWidget.data, contains('Confidence:'));

    audioCaptureService.dispose();
    await streamController.close();
  });

  testWidgets(
    'guitar tuner card updates string, note, status, cents, and frequencies when 110 Hz A2 is played',
    (WidgetTester tester) async {
      final streamController = StreamController<dynamic>.broadcast();
      final audioCaptureService = AudioCaptureService(
        testStream: streamController.stream,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      await tester.pumpWidget(
        ResoHertzApp(
          microphoneService: micService,
          audioCaptureService: audioCaptureService,
        ),
      );
      await tester.pumpAndSettle();

      // Start listening
      await tester.ensureVisible(find.byKey(const Key('start_capture_button')));
      await tester.tap(find.byKey(const Key('start_capture_button')));
      await tester.pump();

      // Emit 110.0 Hz sine wave buffer (2048 samples)
      final buffer = ByteData(2048 * 2);
      for (int i = 0; i < 2048; i++) {
        final t = i / 44100.0;
        final sample = (math.sin(2 * math.pi * 110.0 * t) * 0.8 * 32767)
            .round();
        buffer.setInt16(i * 2, sample, Endian.little);
      }
      streamController.add(buffer.buffer.asUint8List());

      await tester.pump();

      // Verify string label identifies String 5 (A2)
      final stringFinder = find.byKey(const Key('tuner_string_label'));
      expect(stringFinder, findsOneWidget);
      final Text stringText = tester.widget(stringFinder);
      expect(stringText.data, contains('String 5 (A2)'));

      // Verify Note display shows 'A' and octave '2'
      final noteFinder = find.byKey(const Key('note_name_display'));
      expect(noteFinder, findsOneWidget);
      final Text noteText = tester.widget(noteFinder);
      expect(noteText.data, 'A');

      final octaveFinder = find.byKey(const Key('note_octave_display'));
      expect(octaveFinder, findsOneWidget);
      final Text octaveText = tester.widget(octaveFinder);
      expect(octaveText.data, '2');

      // Verify In-Tune badge
      final statusFinder = find.byKey(const Key('tuning_status_badge'));
      expect(statusFinder, findsOneWidget);
      expect(find.text('IN TUNE'), findsOneWidget);

      // Verify Cents and frequency comparison
      final centsFinder = find.byKey(const Key('cents_display'));
      expect(centsFinder, findsOneWidget);
      final Text centsText = tester.widget(centsFinder);
      expect(centsText.data, contains('cents'));

      final freqCompFinder = find.byKey(const Key('frequency_comparison'));
      expect(freqCompFinder, findsOneWidget);
      final Text freqCompText = tester.widget(freqCompFinder);
      expect(freqCompText.data, contains('110.0 / 110.0 Hz'));

      audioCaptureService.dispose();
      await streamController.close();
    },
  );

  testWidgets(
    'reference frequency controls update A4 pitch display and target string frequency dynamically',
    (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      await tester.pumpWidget(ResoHertzApp(microphoneService: micService));
      await tester.pumpAndSettle();

      // Initial reference pitch is 440 Hz
      final refDisplay = find.byKey(const Key('ref_freq_display'));
      expect(refDisplay, findsOneWidget);
      expect((tester.widget(refDisplay) as Text).data, 'A4 = 440 Hz');

      // Tap 432 Hz chip
      await tester.ensureVisible(find.byKey(const Key('ref_freq_432')));
      await tester.tap(find.byKey(const Key('ref_freq_432')));
      await tester.pump();
      expect((tester.widget(refDisplay) as Text).data, 'A4 = 432 Hz');

      // Tap 442 Hz chip
      await tester.ensureVisible(find.byKey(const Key('ref_freq_442')));
      await tester.tap(find.byKey(const Key('ref_freq_442')));
      await tester.pump();
      expect((tester.widget(refDisplay) as Text).data, 'A4 = 442 Hz');

      // Verify Slider exists and reflects 442 Hz
      final sliderFinder = find.byKey(const Key('ref_freq_slider'));
      expect(sliderFinder, findsOneWidget);
      final Slider slider = tester.widget(sliderFinder);
      expect(slider.value, 442.0);

      // Tap 440 Hz chip to return to standard concert pitch
      await tester.ensureVisible(find.byKey(const Key('ref_freq_440')));
      await tester.tap(find.byKey(const Key('ref_freq_440')));
      await tester.pump();
      expect((tester.widget(refDisplay) as Text).data, 'A4 = 440 Hz');
      expect((tester.widget(sliderFinder) as Slider).value, 440.0);
    },
  );

  testWidgets(
    'alternate tuning presets switch target notes and tune Drop D correctly',
    (WidgetTester tester) async {
      final streamController = StreamController<dynamic>.broadcast();
      final audioCaptureService = AudioCaptureService(
        testStream: streamController.stream,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      await tester.pumpWidget(
        ResoHertzApp(
          microphoneService: micService,
          audioCaptureService: audioCaptureService,
        ),
      );
      await tester.pumpAndSettle();

      final labelFinder = find.byKey(const Key('tuner_string_label'));
      expect(labelFinder, findsOneWidget);
      expect(
        (tester.widget(labelFinder) as Text).data,
        'Standard Tuning (E A D G B E)',
      );

      // Open tuning bottom sheet and tap Drop D preset chip
      await tester.ensureVisible(
        find.byKey(const Key('open_tuning_sheet_button')),
      );
      await tester.tap(find.byKey(const Key('open_tuning_sheet_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('preset_chip_drop_d')));
      await tester.tap(find.byKey(const Key('preset_chip_drop_d')));
      await tester.pumpAndSettle();
      expect((tester.widget(labelFinder) as Text).data, 'Drop D (D A D G B E)');

      // Start listening
      await tester.ensureVisible(find.byKey(const Key('start_capture_button')));
      await tester.tap(find.byKey(const Key('start_capture_button')));
      await tester.pump();

      // Emit 73.42 Hz sine wave buffer (2048 samples) for Drop D low 6th string
      final buffer = ByteData(2048 * 2);
      for (int i = 0; i < 2048; i++) {
        final t = i / 44100.0;
        final sample = (math.sin(2 * math.pi * 73.416 * t) * 0.8 * 32767)
            .round();
        buffer.setInt16(i * 2, sample, Endian.little);
      }
      streamController.add(buffer.buffer.asUint8List());

      await tester.pump();

      // Verify String 6 (D2) is detected
      expect(
        (tester.widget(labelFinder) as Text).data,
        contains('String 6 (D2)'),
      );
      final noteFinder = find.byKey(const Key('note_name_display'));
      expect((tester.widget(noteFinder) as Text).data, 'D');
      final octaveFinder = find.byKey(const Key('note_octave_display'));
      expect((tester.widget(octaveFinder) as Text).data, '2');

      // Verify status is IN TUNE
      expect(find.text('IN TUNE'), findsOneWidget);

      audioCaptureService.dispose();
      await streamController.close();
    },
  );

  testWidgets(
    'creates a custom tuning, edits it, and deletes it with confirmation',
    (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') {
              return true;
            }
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      final inMemoryStorage = CustomTuningStorage.inMemory();

      await tester.pumpWidget(
        ResoHertzApp(
          microphoneService: micService,
          customTuningStorage: inMemoryStorage,
        ),
      );
      await tester.pumpAndSettle();

      // Open tuning bottom sheet and tap "+ Custom" chip
      await tester.ensureVisible(
        find.byKey(const Key('open_tuning_sheet_button')),
      );
      await tester.tap(find.byKey(const Key('open_tuning_sheet_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('create_custom_tuning_chip')),
      );
      await tester.tap(find.byKey(const Key('create_custom_tuning_chip')));
      await tester.pumpAndSettle();

      // CustomTuningDialog should be displayed
      expect(find.text('New Custom Tuning'), findsOneWidget);

      // Enter tuning name
      final nameField = find.byKey(const Key('custom_tuning_name_field'));
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Drop D Custom');

      // Decrement String 6 pitch twice: E2 -> D#2 -> D2
      final decStr6 = find.byKey(const Key('decrement_string_6'));
      await tester.tap(decStr6);
      await tester.pump();
      await tester.tap(decStr6);
      await tester.pump();

      // String 6 should now display D2
      expect(find.byKey(const Key('string_display_6')), findsOneWidget);
      expect(
        (tester.widget(find.byKey(const Key('string_display_6'))) as Text).data,
        'D2',
      );

      // Tap Save button
      await tester.tap(find.byKey(const Key('custom_tuning_save_button')));
      await tester.pumpAndSettle();

      // Verify custom tuning is selected and banner appears
      expect(find.text('Custom: Drop D Custom'), findsOneWidget);
      final labelFinder = find.byKey(const Key('tuner_string_label'));
      expect(
        (tester.widget(labelFinder) as Text).data,
        contains('Drop D Custom'),
      );

      // Verify stored in storage
      final stored = await inMemoryStorage.loadCustomTunings();
      expect(stored.length, 1);
      expect(stored.first.name, 'Drop D Custom');
      expect(stored.first.strings.first.displayName, 'D2');

      // Now EDIT the custom tuning
      await tester.tap(find.byKey(const Key('edit_custom_tuning_button')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Custom Tuning'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('custom_tuning_name_field')),
        'Drop D Renamed',
      );
      await tester.tap(find.byKey(const Key('custom_tuning_save_button')));
      await tester.pumpAndSettle();

      // Verify updated name
      expect(find.text('Custom: Drop D Renamed'), findsOneWidget);

      // Now DELETE the custom tuning
      await tester.tap(find.byKey(const Key('delete_custom_tuning_button')));
      await tester.pumpAndSettle();

      // Delete confirmation dialog
      expect(find.text('Delete Custom Tuning?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_delete_tuning_button')));
      await tester.pumpAndSettle();

      // Verify deleted from storage and reset to Standard Tuning
      expect(await inMemoryStorage.loadCustomTunings(), isEmpty);
      expect(
        (tester.widget(labelFinder) as Text).data,
        'Standard Tuning (E A D G B E)',
      );
    },
  );

  testWidgets(
    'toggles favorite tuning on active preset and filters by favorites chip',
    (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      final settingsService = AppSettingsService.inMemory(
        const AppSettings(favoriteTuningIds: ['standard']),
      );

      await tester.pumpWidget(
        ResoHertzApp(
          microphoneService: micService,
          appSettingsService: settingsService,
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Drop D preset via bottom sheet
      await tester.ensureVisible(
        find.byKey(const Key('open_tuning_sheet_button')),
      );
      await tester.tap(find.byKey(const Key('open_tuning_sheet_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('preset_chip_drop_d')));
      await tester.tap(find.byKey(const Key('preset_chip_drop_d')));
      await tester.pumpAndSettle();

      // Drop D is not in favorites yet
      expect(settingsService.currentSettings.isFavorite('drop_d'), isFalse);

      // Tap favorite star on active preset
      await tester.ensureVisible(
        find.byKey(const Key('toggle_fav_active_preset')),
      );
      await tester.tap(find.byKey(const Key('toggle_fav_active_preset')));
      await tester.pumpAndSettle();

      // Now Drop D should be favorited
      expect(settingsService.currentSettings.isFavorite('drop_d'), isTrue);

      // Open bottom sheet and filter by Favorites
      await tester.ensureVisible(
        find.byKey(const Key('open_tuning_sheet_button')),
      );
      await tester.tap(find.byKey(const Key('open_tuning_sheet_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('favorites_filter_chip')),
      );
      await tester.tap(find.byKey(const Key('favorites_filter_chip')));
      await tester.pumpAndSettle();

      // In favorites filter mode: both Standard and Drop D chips are visible
      expect(find.byKey(const Key('preset_chip_standard')), findsOneWidget);
      expect(find.byKey(const Key('preset_chip_drop_d')), findsOneWidget);
      // D Standard was not favorited so it should not be present
      expect(find.byKey(const Key('preset_chip_d_standard')), findsNothing);

      // Close the bottom sheet
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Remove Drop D from favorites
      await tester.ensureVisible(
        find.byKey(const Key('toggle_fav_active_preset')),
      );
      await tester.tap(find.byKey(const Key('toggle_fav_active_preset')));
      await tester.pumpAndSettle();
      expect(settingsService.currentSettings.isFavorite('drop_d'), isFalse);
    },
  );

  testWidgets(
    'opens settings dialog, changes auto-start and prefer # notation, and saves',
    (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      final settingsService = AppSettingsService.inMemory();

      await tester.pumpWidget(
        ResoHertzApp(
          microphoneService: micService,
          appSettingsService: settingsService,
        ),
      );
      await tester.pumpAndSettle();

      // Tap settings button in AppBar
      await tester.tap(find.byKey(const Key('settings_button')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byKey(const Key('auto_start_switch')), findsOneWidget);
      expect(find.byKey(const Key('prefer_sharps_switch')), findsOneWidget);
      expect(find.text('©BAZUD3V'), findsOneWidget);

      // Toggle auto-start and prefer # notation
      await tester.tap(find.byKey(const Key('auto_start_switch')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('prefer_sharps_switch')));
      await tester.pump();

      // Tap Save button
      await tester.tap(find.byKey(const Key('settings_save_button')));
      await tester.pumpAndSettle();

      // Verify settings persisted
      expect(settingsService.currentSettings.autoStartListening, isTrue);
      expect(settingsService.currentSettings.preferFlats, isTrue);
    },
  );

  testWidgets(
    'restores saved reference frequency and last selected tuning on startup',
    (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      final settingsService = AppSettingsService.inMemory(
        const AppSettings(referenceA4: 442.0, lastSelectedTuningId: 'drop_d'),
      );

      await tester.pumpWidget(
        ResoHertzApp(
          microphoneService: micService,
          appSettingsService: settingsService,
        ),
      );
      await tester.pumpAndSettle();

      // Verify restored reference frequency A4 = 442 Hz
      expect(find.text('A4 = 442 Hz'), findsOneWidget);

      // Verify restored tuning is Drop D
      final labelFinder = find.byKey(const Key('tuner_string_label'));
      expect((tester.widget(labelFinder) as Text).data, 'Drop D (D A D G B E)');
    },
  );

  testWidgets(
    'dedicated brand theme uses French Blue and Lime Yellow and displays app logo',
    (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      final settingsService = AppSettingsService.inMemory();

      await tester.pumpWidget(
        ResoHertzApp(
          microphoneService: micService,
          appSettingsService: settingsService,
        ),
      );
      await tester.pumpAndSettle();

      // Verify app logo is displayed in AppBar
      expect(find.byKey(const Key('app_logo_image')), findsOneWidget);

      // Verify brand theme background color
      final scaffoldContext = tester.element(find.byType(Scaffold));
      expect(
        Theme.of(scaffoldContext).scaffoldBackgroundColor,
        const Color(0xFF0055A4),
      );
    },
  );

  testWidgets(
    'Phase 11: 6-string headstock visualizer displays all strings and highlights plucked string #5 on A2',
    (WidgetTester tester) async {
      final streamController = StreamController<dynamic>.broadcast();
      final audioCaptureService = AudioCaptureService(
        testStream: streamController.stream,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      await tester.pumpWidget(
        ResoHertzApp(
          microphoneService: micService,
          audioCaptureService: audioCaptureService,
        ),
      );
      await tester.pumpAndSettle();

      // Verify headstock visualizer is rendered
      expect(
        find.byKey(const Key('guitar_headstock_visualizer')),
        findsOneWidget,
      );
      // Verify all 6 string numbers are shown (#6 through #1)
      expect(find.text('#6'), findsOneWidget);
      expect(find.text('#5'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);

      // Start listening
      await tester.ensureVisible(find.byKey(const Key('start_capture_button')));
      await tester.tap(find.byKey(const Key('start_capture_button')));
      await tester.pump();

      // Emit 110 Hz sine wave (A2 -> String #5)
      final buffer = ByteData(2048 * 2);
      for (int i = 0; i < 2048; i++) {
        final t = i / 44100.0;
        final sample = (math.sin(2 * math.pi * 110.0 * t) * 0.8 * 32767)
            .round();
        buffer.setInt16(i * 2, sample, Endian.little);
      }
      streamController.add(buffer.buffer.asUint8List());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Note display shows A
      expect(find.byKey(const Key('note_name_display')), findsOneWidget);
      final Text noteText = tester.widget(
        find.byKey(const Key('note_name_display')),
      );
      expect(noteText.data, 'A');

      audioCaptureService.dispose();
      await streamController.close();
    },
  );

  testWidgets(
    'single tuning icon button opens Material bottom sheet with tunings & favorites, allows selection',
    (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermission') return true;
            if (methodCall.method == 'hasPermission') return true;
            if (methodCall.method == 'requestPermission') return true;
            if (methodCall.method == 'initializeMicrophone') {
              return <dynamic, dynamic>{
                'isAvailable': true,
                'sampleRate': 44100,
                'minBufferSize': 3584,
                'error': null,
              };
            }
            return null;
          });

      await tester.pumpWidget(ResoHertzApp(microphoneService: micService));
      await tester.pumpAndSettle();

      // Find tuning icon button and verify initial state
      final tuningButton = find.byKey(const Key('open_tuning_sheet_button'));
      expect(tuningButton, findsOneWidget);
      expect(find.byKey(const Key('tuning_icon')), findsOneWidget);

      // Tap to open bottom sheet
      await tester.tap(tuningButton);
      await tester.pumpAndSettle();

      // Verify bottom sheet contents
      expect(find.text('Select Tuning'), findsOneWidget);
      expect(find.byKey(const Key('favorites_filter_chip')), findsOneWidget);
      expect(
        find.byKey(const Key('create_custom_tuning_chip')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('preset_chip_standard')), findsOneWidget);
      expect(find.byKey(const Key('preset_chip_drop_d')), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);

      // Select Drop D from the bottom sheet
      await tester.tap(find.byKey(const Key('preset_chip_drop_d')));
      await tester.pumpAndSettle();

      // Bottom sheet should close and active tuning should now be Drop D
      expect(find.text('Select Tuning'), findsNothing);
      expect(
        (tester.widget(find.byKey(const Key('tuner_string_label'))) as Text)
            .data,
        'Drop D (D A D G B E)',
      );
    },
  );
}
