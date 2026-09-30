import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/tuning/custom_tuning_storage.dart';
import 'package:resohertz/tuning/guitar_string.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GuitarString - MIDI & JSON Serialization', () {
    test('GuitarString.fromMidi correctly derives noteName and octave', () {
      final e2 = GuitarString.fromMidi(stringNumber: 6, midiNote: 40);
      expect(e2.noteName, 'E');
      expect(e2.octave, 2);
      expect(e2.displayName, 'E2');
      expect(e2.midiNote, 40);

      final d2 = GuitarString.fromMidi(stringNumber: 6, midiNote: 38);
      expect(d2.noteName, 'D');
      expect(d2.octave, 2);
      expect(d2.displayName, 'D2');

      final c4 = GuitarString.fromMidi(stringNumber: 1, midiNote: 60);
      expect(c4.noteName, 'C');
      expect(c4.octave, 4);
      expect(c4.displayName, 'C4');

      final a4 = GuitarString.fromMidi(stringNumber: 1, midiNote: 69);
      expect(a4.noteName, 'A');
      expect(a4.octave, 4);
      expect(a4.displayName, 'A4');
    });

    test('GuitarString.withMidiNote transposes string accurately', () {
      final s = const GuitarString(
        stringNumber: 6,
        noteName: 'E',
        octave: 2,
        midiNote: 40,
      );
      final transposedDown = s.withMidiNote(38); // D2
      expect(transposedDown.stringNumber, 6);
      expect(transposedDown.noteName, 'D');
      expect(transposedDown.octave, 2);
      expect(transposedDown.midiNote, 38);

      final transposedUp = s.withMidiNote(41); // F2
      expect(transposedUp.noteName, 'F');
      expect(transposedUp.octave, 2);
      expect(transposedUp.midiNote, 41);
    });

    test('GuitarString toJson and fromJson round-trip accurately', () {
      const original = GuitarString(
        stringNumber: 3,
        noteName: 'G',
        octave: 3,
        midiNote: 55,
      );
      final json = original.toJson();
      final restored = GuitarString.fromJson(json);

      expect(restored.stringNumber, original.stringNumber);
      expect(restored.noteName, original.noteName);
      expect(restored.octave, original.octave);
      expect(restored.midiNote, original.midiNote);
      expect(restored, equals(original));
    });
  });

  group('TuningPreset - Custom Tunings & JSON Serialization', () {
    test('builtInPresets have isCustom=false', () {
      for (final preset in TuningPreset.builtInPresets) {
        expect(preset.isCustom, isFalse);
      }
    });

    test('TuningPreset.copyWith preserves or updates isCustom and fields', () {
      const standard = TuningPreset.standard;
      final custom = standard.copyWith(
        id: 'my_custom_1',
        name: 'My Custom Standard',
        isCustom: true,
      );

      expect(custom.id, 'my_custom_1');
      expect(custom.name, 'My Custom Standard');
      expect(custom.isCustom, isTrue);
      expect(custom.strings.length, 6);
    });

    test('TuningPreset toJson and fromJson round-trip accurately', () {
      final custom = TuningPreset(
        id: 'drop_b_custom',
        name: 'Drop B',
        isCustom: true,
        strings: [
          GuitarString.fromMidi(stringNumber: 6, midiNote: 35), // B1
          GuitarString.fromMidi(stringNumber: 5, midiNote: 42), // F#2
          GuitarString.fromMidi(stringNumber: 4, midiNote: 47), // B2
          GuitarString.fromMidi(stringNumber: 3, midiNote: 52), // E3
          GuitarString.fromMidi(stringNumber: 2, midiNote: 56), // G#3
          GuitarString.fromMidi(stringNumber: 1, midiNote: 61), // C#4
        ],
      );

      final json = custom.toJson();
      final restored = TuningPreset.fromJson(json);

      expect(restored.id, custom.id);
      expect(restored.name, custom.name);
      expect(restored.isCustom, isTrue);
      expect(restored.strings.length, 6);
      expect(restored.strings[0].displayName, 'B1');
      expect(restored.strings[1].displayName, 'F♯2');
    });
  });

  group('CustomTuningStorage - In-Memory Operations', () {
    late CustomTuningStorage storage;

    setUp(() {
      storage = CustomTuningStorage.inMemory();
    });

    test('loads empty list initially', () async {
      final tunings = await storage.loadCustomTunings();
      expect(tunings, isEmpty);
    });

    test('adds custom tuning and persists in storage', () async {
      final preset = TuningPreset(
        id: 'custom_1',
        name: 'Open C',
        strings: [
          GuitarString.fromMidi(stringNumber: 6, midiNote: 36), // C2
          GuitarString.fromMidi(stringNumber: 5, midiNote: 43), // G2
          GuitarString.fromMidi(stringNumber: 4, midiNote: 48), // C3
          GuitarString.fromMidi(stringNumber: 3, midiNote: 55), // G3
          GuitarString.fromMidi(stringNumber: 2, midiNote: 60), // C4
          GuitarString.fromMidi(stringNumber: 1, midiNote: 64), // E4
        ],
      );

      await storage.addCustomTuning(preset);
      final loaded = await storage.loadCustomTunings();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'custom_1');
      expect(loaded.first.name, 'Open C');
      expect(loaded.first.isCustom, isTrue);
    });

    test('updates existing custom tuning', () async {
      final preset = TuningPreset(
        id: 'custom_1',
        name: 'Open C Initial',
        isCustom: true,
        strings: TuningPreset.standard.strings,
      );
      await storage.addCustomTuning(preset);

      final updated = preset.copyWith(name: 'Open C Renamed');
      await storage.updateCustomTuning(updated);

      final loaded = await storage.loadCustomTunings();
      expect(loaded.length, 1);
      expect(loaded.first.name, 'Open C Renamed');
    });

    test('deletes custom tuning by id', () async {
      final preset1 = TuningPreset(
        id: 'custom_1',
        name: 'Custom 1',
        strings: TuningPreset.standard.strings,
      );
      final preset2 = TuningPreset(
        id: 'custom_2',
        name: 'Custom 2',
        strings: TuningPreset.standard.strings,
      );

      await storage.addCustomTuning(preset1);
      await storage.addCustomTuning(preset2);
      expect((await storage.loadCustomTunings()).length, 2);

      await storage.deleteCustomTuning('custom_1');
      final loaded = await storage.loadCustomTunings();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'custom_2');
    });

    test('clearAll clears all custom tunings', () async {
      final preset = TuningPreset(
        id: 'custom_1',
        name: 'Custom 1',
        strings: TuningPreset.standard.strings,
      );
      await storage.addCustomTuning(preset);
      expect((await storage.loadCustomTunings()).length, 1);

      await storage.clearAll();
      expect((await storage.loadCustomTunings()), isEmpty);
    });
  });

  group('CustomTuningStorage - Platform MethodChannel Integration', () {
    const channel = MethodChannel(CustomTuningStorage.channelName);
    String? mockStorageJson;

    setUp(() {
      mockStorageJson = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            switch (methodCall.method) {
              case 'saveCustomTunings':
                final args = methodCall.arguments as Map;
                mockStorageJson = args['json'] as String?;
                return true;
              case 'loadCustomTunings':
                return mockStorageJson;
              case 'clearCustomTunings':
                mockStorageJson = null;
                return true;
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('saves and loads from native channel json', () async {
      final storage = CustomTuningStorage(channel: channel);

      // Initially empty
      final initial = await storage.loadCustomTunings();
      expect(initial, isEmpty);

      // Save custom tuning
      final preset = TuningPreset(
        id: 'native_custom_1',
        name: 'Native Test Tuning',
        strings: TuningPreset.standard.strings,
      );
      await storage.addCustomTuning(preset);

      expect(mockStorageJson, isNotNull);
      final decodedJson = jsonDecode(mockStorageJson!) as List;
      expect(decodedJson.length, 1);
      expect(decodedJson[0]['id'], 'native_custom_1');

      // Create a fresh storage instance and load
      final newStorage = CustomTuningStorage(channel: channel);
      final loaded = await newStorage.loadCustomTunings();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'native_custom_1');
      expect(loaded.first.name, 'Native Test Tuning');
      expect(loaded.first.isCustom, isTrue);
    });
  });
}
