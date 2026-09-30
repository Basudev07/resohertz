import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

/// Service responsible for persisting and managing user-created custom guitar tunings.
///
/// Uses Android native SharedPreferences via MethodChannel ('com.resohertz/storage')
/// with zero external dependencies, while maintaining an in-memory cache for fast,
/// synchronous reads and headless test environments.
class CustomTuningStorage {
  static const String channelName = 'com.resohertz/storage';
  static const MethodChannel _defaultChannel = MethodChannel(channelName);

  final MethodChannel? _channel;
  List<TuningPreset>? _cachedTunings;

  /// Default constructor using the native platform MethodChannel.
  CustomTuningStorage({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  /// In-memory constructor for fast, isolated unit and widget tests.
  CustomTuningStorage.inMemory([List<TuningPreset>? initialTunings])
    : _channel = null,
      _cachedTunings = initialTunings != null
          ? List<TuningPreset>.from(initialTunings)
          : <TuningPreset>[];

  /// Loads all saved custom tuning presets from local storage.
  /// Returns an empty list if no custom tunings have been saved.
  Future<List<TuningPreset>> loadCustomTunings() async {
    if (_channel == null) {
      return List<TuningPreset>.unmodifiable(_cachedTunings ?? []);
    }

    try {
      final String? jsonStr = await _channel.invokeMethod<String>(
        'loadCustomTunings',
      );
      if (jsonStr == null || jsonStr.trim().isEmpty) {
        _cachedTunings = [];
        return [];
      }

      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        final List<TuningPreset> presets = decoded
            .map(
              (item) =>
                  TuningPreset.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
        _cachedTunings = presets;
        return List<TuningPreset>.unmodifiable(presets);
      }
      _cachedTunings = [];
      return [];
    } on MissingPluginException {
      // In headless test environments without mock channels
      return List<TuningPreset>.unmodifiable(_cachedTunings ?? []);
    } catch (_) {
      return List<TuningPreset>.unmodifiable(_cachedTunings ?? []);
    }
  }

  /// Persists the complete list of [customPresets] to local storage.
  Future<void> saveCustomTunings(List<TuningPreset> customPresets) async {
    final list = List<TuningPreset>.from(customPresets);
    _cachedTunings = list;

    if (_channel == null) return;

    try {
      final jsonStr = jsonEncode(list.map((p) => p.toJson()).toList());
      await _channel.invokeMethod<bool>('saveCustomTunings', {'json': jsonStr});
    } on MissingPluginException {
      // Handled silently for test runners
    } catch (e) {
      // Log or handle error if needed
    }
  }

  /// Adds a new [preset] (marked as custom) and persists it.
  Future<void> addCustomTuning(TuningPreset preset) async {
    final current = List<TuningPreset>.from(await loadCustomTunings());
    final toAdd = preset.isCustom ? preset : preset.copyWith(isCustom: true);
    current.add(toAdd);
    await saveCustomTunings(current);
  }

  /// Updates an existing custom tuning matching [updated.id].
  Future<void> updateCustomTuning(TuningPreset updated) async {
    final current = List<TuningPreset>.from(await loadCustomTunings());
    final index = current.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      current[index] = updated.isCustom
          ? updated
          : updated.copyWith(isCustom: true);
      await saveCustomTunings(current);
    } else {
      await addCustomTuning(updated);
    }
  }

  /// Deletes a custom tuning by its [presetId].
  Future<void> deleteCustomTuning(String presetId) async {
    final current = List<TuningPreset>.from(await loadCustomTunings());
    current.removeWhere((p) => p.id == presetId);
    await saveCustomTunings(current);
  }

  /// Clears all custom tunings from local storage.
  Future<void> clearAll() async {
    _cachedTunings = [];
    if (_channel == null) return;

    try {
      await _channel.invokeMethod<bool>('clearCustomTunings');
    } catch (_) {}
  }
}
