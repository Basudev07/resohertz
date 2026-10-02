import 'package:resohertz/tuning/reference_frequency.dart';

/// User preferences and configuration settings for Reso Hertz.
class AppSettings {
  /// Reference pitch calibration frequency in Hertz (e.g. 440.0, 432.0, 442.0).
  final double referenceA4;

  /// ID of the last active tuning preset (e.g. 'standard', 'drop_d', or custom ID).
  final String lastSelectedTuningId;

  /// List of tuning preset IDs marked as favorites.
  final List<String> favoriteTuningIds;

  /// In-tune tolerance window in musical cents (e.g. 2.0 = strict, 3.0 = standard, 5.0 = relaxed).
  final double inTuneToleranceCents;

  /// Whether to automatically start listening when the app opens.
  final bool autoStartListening;

  /// Whether to prefer flat note notation (e.g. E♭, B♭) instead of sharp notation (D♯, A♯).
  final bool preferFlats;

  /// UI Theme Mode: 'dark', 'light', or 'system'.
  final String themeMode;

  /// Background visual style: 'classic' (French Blue with lime glow, default) or 'aurora' (Chromatic Aurora).
  final String backgroundStyle;

  /// Whether tactile haptic vibration is enabled on in-tune locks.
  final bool hapticEnabled;

  /// Whether audio chime feedback (success.mp3) is enabled on in-tune locks.
  final bool soundEnabled;

  const AppSettings({
    this.referenceA4 = ReferenceFrequency.standard,
    this.lastSelectedTuningId = 'standard',
    this.favoriteTuningIds = const ['standard', 'drop_d'],
    this.inTuneToleranceCents = 3.0,
    this.autoStartListening = false,
    this.preferFlats = false,
    this.themeMode = 'dark',
    this.backgroundStyle = 'classic',
    this.hapticEnabled = true,
    this.soundEnabled = true,
  });

  /// Factory for default factory settings.
  static const AppSettings defaultSettings = AppSettings();

  /// Checks if [tuningId] is currently marked as a favorite.
  bool isFavorite(String tuningId) => favoriteTuningIds.contains(tuningId);

  /// Returns a copy with [tuningId] added or removed from favorites.
  AppSettings toggleFavorite(String tuningId) {
    final list = List<String>.from(favoriteTuningIds);
    if (list.contains(tuningId)) {
      list.remove(tuningId);
    } else {
      list.add(tuningId);
    }
    return copyWith(favoriteTuningIds: list);
  }

  /// Returns a copy of [AppSettings] with updated fields.
  AppSettings copyWith({
    double? referenceA4,
    String? lastSelectedTuningId,
    List<String>? favoriteTuningIds,
    double? inTuneToleranceCents,
    bool? autoStartListening,
    bool? preferFlats,
    String? themeMode,
    String? backgroundStyle,
    bool? hapticEnabled,
    bool? soundEnabled,
  }) {
    return AppSettings(
      referenceA4: referenceA4 ?? this.referenceA4,
      lastSelectedTuningId: lastSelectedTuningId ?? this.lastSelectedTuningId,
      favoriteTuningIds: favoriteTuningIds ?? this.favoriteTuningIds,
      inTuneToleranceCents: inTuneToleranceCents ?? this.inTuneToleranceCents,
      autoStartListening: autoStartListening ?? this.autoStartListening,
      preferFlats: preferFlats ?? this.preferFlats,
      themeMode: themeMode ?? this.themeMode,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
    );
  }

  /// Serializes settings into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'referenceA4': referenceA4,
    'lastSelectedTuningId': lastSelectedTuningId,
    'favoriteTuningIds': favoriteTuningIds,
    'inTuneToleranceCents': inTuneToleranceCents,
    'autoStartListening': autoStartListening,
    'preferFlats': preferFlats,
    'themeMode': themeMode,
    'backgroundStyle': backgroundStyle,
    'hapticEnabled': hapticEnabled,
    'soundEnabled': soundEnabled,
  };

  /// Deserializes settings from a JSON map.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawFavorites =
        json['favoriteTuningIds'] as List<dynamic>? ?? ['standard', 'drop_d'];
    return AppSettings(
      referenceA4:
          (json['referenceA4'] as num?)?.toDouble() ??
          ReferenceFrequency.standard,
      lastSelectedTuningId:
          json['lastSelectedTuningId'] as String? ?? 'standard',
      favoriteTuningIds: rawFavorites.map((e) => e.toString()).toList(),
      inTuneToleranceCents:
          (json['inTuneToleranceCents'] as num?)?.toDouble() ?? 3.0,
      autoStartListening: json['autoStartListening'] as bool? ?? false,
      preferFlats: json['preferFlats'] as bool? ?? false,
      themeMode: json['themeMode'] as String? ?? 'dark',
      backgroundStyle: json['backgroundStyle'] as String? ?? 'classic',
      hapticEnabled: json['hapticEnabled'] as bool? ?? true,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          referenceA4 == other.referenceA4 &&
          lastSelectedTuningId == other.lastSelectedTuningId &&
          inTuneToleranceCents == other.inTuneToleranceCents &&
          autoStartListening == other.autoStartListening &&
          preferFlats == other.preferFlats &&
          themeMode == other.themeMode &&
          backgroundStyle == other.backgroundStyle &&
          hapticEnabled == other.hapticEnabled &&
          soundEnabled == other.soundEnabled &&
          _listEquals(favoriteTuningIds, other.favoriteTuningIds);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      referenceA4.hashCode ^
      lastSelectedTuningId.hashCode ^
      favoriteTuningIds.hashCode ^
      inTuneToleranceCents.hashCode ^
      autoStartListening.hashCode ^
      preferFlats.hashCode ^
      themeMode.hashCode ^
      backgroundStyle.hashCode ^
      hapticEnabled.hashCode ^
      soundEnabled.hashCode;
}
