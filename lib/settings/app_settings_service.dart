import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:resohertz/settings/app_settings.dart';

/// Service managing persistent user settings and tuning preferences via Android native SharedPreferences.
class AppSettingsService {
  static const String channelName = 'com.resohertz/storage';
  static const MethodChannel _defaultChannel = MethodChannel(channelName);

  final MethodChannel? _channel;
  AppSettings _cachedSettings;

  /// Default constructor connecting to native platform channel.
  AppSettingsService({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel,
      _cachedSettings = AppSettings.defaultSettings;

  /// In-memory constructor for unit and widget testing.
  AppSettingsService.inMemory([AppSettings? initialSettings])
    : _channel = null,
      _cachedSettings = initialSettings ?? AppSettings.defaultSettings;

  /// Current in-memory cached settings for fast synchronous access.
  AppSettings get currentSettings => _cachedSettings;

  /// Loads saved settings from local storage.
  /// Falls back to default settings if none exist or on error.
  Future<AppSettings> loadSettings() async {
    if (_channel == null) {
      return _cachedSettings;
    }

    try {
      final String? jsonStr = await _channel.invokeMethod<String>(
        'loadSettings',
      );
      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return _cachedSettings;
      }

      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        _cachedSettings = AppSettings.fromJson(decoded);
      } else if (decoded is Map) {
        _cachedSettings = AppSettings.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
      return _cachedSettings;
    } on MissingPluginException {
      return _cachedSettings;
    } catch (_) {
      return _cachedSettings;
    }
  }

  /// Persists [settings] to local storage.
  Future<void> saveSettings(AppSettings settings) async {
    _cachedSettings = settings;

    if (_channel == null) return;

    try {
      final jsonStr = jsonEncode(settings.toJson());
      await _channel.invokeMethod<bool>('saveSettings', {'json': jsonStr});
    } on MissingPluginException {
      // Ignored for tests
    } catch (_) {
      // Ignored
    }
  }

  /// Clears stored settings and restores defaults.
  Future<void> clearSettings() async {
    _cachedSettings = AppSettings.defaultSettings;
    if (_channel == null) return;

    try {
      await _channel.invokeMethod<bool>('clearSettings');
    } catch (_) {}
  }
}
