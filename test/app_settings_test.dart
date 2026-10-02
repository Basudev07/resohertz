import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resohertz/settings/app_settings.dart';
import 'package:resohertz/settings/app_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings Model & Serialization', () {
    test('defaultSettings has expected standard defaults', () {
      const defaults = AppSettings.defaultSettings;
      expect(defaults.referenceA4, 440.0);
      expect(defaults.lastSelectedTuningId, 'standard');
      expect(defaults.favoriteTuningIds, contains('standard'));
      expect(defaults.favoriteTuningIds, contains('drop_d'));
      expect(defaults.inTuneToleranceCents, 3.0);
      expect(defaults.autoStartListening, isFalse);
      expect(defaults.preferFlats, isFalse);
      expect(defaults.backgroundStyle, 'classic');
    });

    test(
      'isFavorite and toggleFavorite correctly modify favoriteTuningIds',
      () {
        const initial = AppSettings(favoriteTuningIds: ['standard']);
        expect(initial.isFavorite('standard'), isTrue);
        expect(initial.isFavorite('drop_c'), isFalse);

        final added = initial.toggleFavorite('drop_c');
        expect(added.isFavorite('drop_c'), isTrue);
        expect(added.favoriteTuningIds.length, 2);

        final removed = added.toggleFavorite('standard');
        expect(removed.isFavorite('standard'), isFalse);
        expect(removed.favoriteTuningIds, ['drop_c']);
      },
    );

    test('copyWith updates individual fields', () {
      const s = AppSettings();
      final updated = s.copyWith(
        referenceA4: 432.0,
        inTuneToleranceCents: 2.0,
        preferFlats: true,
        backgroundStyle: 'aurora',
      );

      expect(updated.referenceA4, 432.0);
      expect(updated.inTuneToleranceCents, 2.0);
      expect(updated.preferFlats, isTrue);
      expect(updated.backgroundStyle, 'aurora');
      expect(updated.lastSelectedTuningId, 'standard');
    });

    test('toJson and fromJson round-trip perfectly', () {
      const original = AppSettings(
        referenceA4: 442.0,
        lastSelectedTuningId: 'drop_d',
        favoriteTuningIds: ['standard', 'drop_d', 'dadgad'],
        inTuneToleranceCents: 5.0,
        autoStartListening: true,
        preferFlats: true,
        backgroundStyle: 'aurora',
      );

      final json = original.toJson();
      final restored = AppSettings.fromJson(json);

      expect(restored.referenceA4, original.referenceA4);
      expect(restored.lastSelectedTuningId, original.lastSelectedTuningId);
      expect(restored.favoriteTuningIds, original.favoriteTuningIds);
      expect(restored.inTuneToleranceCents, original.inTuneToleranceCents);
      expect(restored.autoStartListening, original.autoStartListening);
      expect(restored.preferFlats, original.preferFlats);
      expect(restored.backgroundStyle, 'aurora');
      expect(restored, equals(original));
    });
  });

  group('AppSettingsService - In-Memory Operations', () {
    late AppSettingsService service;

    setUp(() {
      service = AppSettingsService.inMemory();
    });

    test('returns default settings when freshly instantiated', () async {
      final settings = await service.loadSettings();
      expect(settings.referenceA4, 440.0);
      expect(settings.lastSelectedTuningId, 'standard');
    });

    test('saves and loads modified settings', () async {
      final updated = AppSettings.defaultSettings.copyWith(
        referenceA4: 436.0,
        lastSelectedTuningId: 'open_d',
      );

      await service.saveSettings(updated);
      final loaded = await service.loadSettings();

      expect(loaded.referenceA4, 436.0);
      expect(loaded.lastSelectedTuningId, 'open_d');
    });

    test('clearSettings resets to factory defaults', () async {
      await service.saveSettings(
        AppSettings.defaultSettings.copyWith(referenceA4: 442.0),
      );
      expect((await service.loadSettings()).referenceA4, 442.0);

      await service.clearSettings();
      expect((await service.loadSettings()).referenceA4, 440.0);
    });
  });

  group('AppSettingsService - Platform MethodChannel Integration', () {
    const channel = MethodChannel(AppSettingsService.channelName);
    String? mockSettingsJson;

    setUp(() {
      mockSettingsJson = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            switch (methodCall.method) {
              case 'saveSettings':
                final args = methodCall.arguments as Map;
                mockSettingsJson = args['json'] as String?;
                return true;
              case 'loadSettings':
                return mockSettingsJson;
              case 'clearSettings':
                mockSettingsJson = null;
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

    test('saves and loads settings from native channel json', () async {
      final service = AppSettingsService(channel: channel);

      // Load initially (should fall back to defaults)
      final initial = await service.loadSettings();
      expect(initial.referenceA4, 440.0);

      // Save custom settings
      const customSettings = AppSettings(
        referenceA4: 432.0,
        lastSelectedTuningId: 'drop_c',
        favoriteTuningIds: ['drop_c'],
        inTuneToleranceCents: 2.0,
      );
      await service.saveSettings(customSettings);

      expect(mockSettingsJson, isNotNull);
      final decoded = jsonDecode(mockSettingsJson!) as Map;
      expect(decoded['referenceA4'], 432.0);
      expect(decoded['lastSelectedTuningId'], 'drop_c');

      // Create new service instance and load
      final newService = AppSettingsService(channel: channel);
      final loaded = await newService.loadSettings();
      expect(loaded.referenceA4, 432.0);
      expect(loaded.lastSelectedTuningId, 'drop_c');
      expect(loaded.inTuneToleranceCents, 2.0);
    });
  });
}
