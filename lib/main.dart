import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resohertz/audio/audio_capture_service.dart';
import 'package:resohertz/audio/audio_feedback_service.dart';
import 'package:resohertz/audio/microphone_service.dart';
import 'package:resohertz/pitch/pitch_result.dart';
import 'package:resohertz/pitch/yin_pitch_detector.dart';
import 'package:resohertz/settings/app_settings.dart';
import 'package:resohertz/settings/app_settings_service.dart';
import 'package:resohertz/settings/settings_dialog.dart';
import 'package:resohertz/tuner/guitar_pick_indicator.dart';
import 'package:resohertz/tuner/pitch_stabilizer.dart';
import 'package:resohertz/tuner/tuner_engine.dart';
import 'package:resohertz/tuner/tuning_result.dart';
import 'package:resohertz/tuning/custom_tuning_dialog.dart';
import 'package:resohertz/tuning/custom_tuning_storage.dart';
import 'package:resohertz/tuning/reference_frequency.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

void main() {
  runApp(const ResoHertzApp());
}

class ResoHertzApp extends StatelessWidget {
  final MicrophoneService microphoneService;
  final AudioCaptureService? audioCaptureService;
  final AudioFeedbackService? audioFeedbackService;
  final TunerEngine tunerEngine;
  final CustomTuningStorage? customTuningStorage;
  final AppSettingsService? appSettingsService;

  const ResoHertzApp({
    super.key,
    this.microphoneService = const MicrophoneService(),
    this.audioCaptureService,
    this.audioFeedbackService,
    this.tunerEngine = const TunerEngine(),
    this.customTuningStorage,
    this.appSettingsService,
  });

  ThemeData _buildBrandTheme() {
    const primary = Color(0xFFDCF4A2);
    const onPrimary = Color(0xFF003366);
    const bg = Color(0xFF0055A4);
    const cardBg = Color(0xFF004382);
    const border = Color(0xFF0068C7);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: Color(0xFF00376B),
        onPrimaryContainer: primary,
        secondary: primary,
        onSecondary: onPrimary,
        surface: cardBg,
        onSurface: primary,
        outline: border,
        outlineVariant: Color(0xFF004F96),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border, width: 1.2),
        ),
        titleTextStyle: const TextStyle(
          color: primary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(
          color: primary.withValues(alpha: 0.9),
          fontSize: 14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brandTheme = _buildBrandTheme();
    return MaterialApp(
      title: 'Reso Hertz',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: brandTheme,
      darkTheme: brandTheme,
      home: TunerHomeScreen(
        microphoneService: microphoneService,
        audioCaptureService: audioCaptureService,
        audioFeedbackService: audioFeedbackService,
        tunerEngine: tunerEngine,
        customTuningStorage: customTuningStorage,
        appSettingsService: appSettingsService,
      ),
    );
  }
}

class TunerHomeScreen extends StatefulWidget {
  final MicrophoneService microphoneService;
  final AudioCaptureService? audioCaptureService;
  final AudioFeedbackService? audioFeedbackService;
  final TunerEngine tunerEngine;
  final CustomTuningStorage? customTuningStorage;
  final AppSettingsService? appSettingsService;
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode>? onThemeChanged;

  const TunerHomeScreen({
    super.key,
    required this.microphoneService,
    this.audioCaptureService,
    this.audioFeedbackService,
    this.tunerEngine = const TunerEngine(),
    this.customTuningStorage,
    this.appSettingsService,
    this.currentThemeMode = ThemeMode.dark,
    this.onThemeChanged,
  });

  @override
  State<TunerHomeScreen> createState() => _TunerHomeScreenState();
}

class _TunerHomeScreenState extends State<TunerHomeScreen>
    with WidgetsBindingObserver {
  late final AudioCaptureService _audioCaptureService;
  late final AudioFeedbackService _audioFeedbackService;
  late final YinPitchDetector _pitchDetector;
  late TunerEngine _tunerEngine;
  final PitchStabilizer _pitchStabilizer = PitchStabilizer();
  double _visualCents = 0.0;

  bool _isChecking = true;
  bool _hasPermission = false;

  bool _isCapturing = false;
  PitchResult _pitchResult = const PitchResult.unpitched();
  TuningResult _tuningResult = const TuningResult.unpitched();
  int _inTuneConsecutiveFrames = 0;
  bool _hasPlayedInTuneSoundForCurrentNote = false;
  int _unpitchedConsecutiveFrames = 0;
  double _referenceA4 = ReferenceFrequency.standard;
  TuningPreset _selectedPreset = TuningPreset.standard;
  String? _captureError;

  late final CustomTuningStorage _customTuningStorage;
  late final AppSettingsService _settingsService;
  List<TuningPreset> _customPresets = [];
  AppSettings _settings = AppSettings.defaultSettings;
  bool _showFavoritesOnly = false;

  List<TuningPreset> get _allPresets => [
    ...TuningPreset.builtInPresets,
    ..._customPresets,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audioCaptureService = widget.audioCaptureService ?? AudioCaptureService();
    _audioFeedbackService =
        widget.audioFeedbackService ?? AudioFeedbackService();
    _pitchDetector = YinPitchDetector(sampleRate: 44100);
    _settingsService = widget.appSettingsService ?? AppSettingsService();
    _settings = _settingsService.currentSettings;
    _referenceA4 = _settings.referenceA4;
    _selectedPreset = TuningPreset.byId(_settings.lastSelectedTuningId);
    _tunerEngine = widget.tunerEngine.copyWith(
      referenceA4: _settings.referenceA4,
      inTuneToleranceCents: _settings.inTuneToleranceCents,
    );
    _customTuningStorage = widget.customTuningStorage ?? CustomTuningStorage();
    _checkAndInit();
    _loadSettingsAndTunings();
  }

  Future<void> _loadSettingsAndTunings() async {
    final settings = await _settingsService.loadSettings();
    final custom = await _customTuningStorage.loadCustomTunings();
    if (!mounted) return;

    final all = [...TuningPreset.builtInPresets, ...custom];
    final initialPreset = all.firstWhere(
      (p) => p.id == settings.lastSelectedTuningId,
      orElse: () => TuningPreset.standard,
    );

    setState(() {
      _settings = settings;
      _customPresets = custom;
      _referenceA4 = settings.referenceA4;
      _selectedPreset = initialPreset;
      _tunerEngine = _tunerEngine.copyWith(
        referenceA4: settings.referenceA4,
        inTuneToleranceCents: settings.inTuneToleranceCents,
      );
    });

    if (settings.autoStartListening && _hasPermission && !_isCapturing) {
      _startCapture();
    }
  }

  Future<void> _openCreateTuningDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => CustomTuningDialog(
        initialTemplate: _selectedPreset,
        referenceA4: _referenceA4,
        onSave: (newPreset) async {
          await _customTuningStorage.addCustomTuning(newPreset);
          if (!mounted) return;
          setState(() {
            _customPresets = [..._customPresets, newPreset];
            _selectedPreset = newPreset;
            if (_pitchResult.isPitched) {
              _tuningResult = _tunerEngine.evaluate(
                pitchResult: _pitchResult,
                preset: newPreset,
                referenceA4: _referenceA4,
              );
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Custom tuning "${newPreset.name}" created.'),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditTuningDialog(TuningPreset preset) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => CustomTuningDialog(
        presetToEdit: preset,
        referenceA4: _referenceA4,
        onSave: (updated) async {
          await _customTuningStorage.updateCustomTuning(updated);
          if (!mounted) return;
          setState(() {
            final index = _customPresets.indexWhere((p) => p.id == updated.id);
            if (index != -1) {
              _customPresets[index] = updated;
            }
            if (_selectedPreset.id == updated.id) {
              _selectedPreset = updated;
              if (_pitchResult.isPitched) {
                _tuningResult = _tunerEngine.evaluate(
                  pitchResult: _pitchResult,
                  preset: updated,
                  referenceA4: _referenceA4,
                );
              }
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Custom tuning "${updated.name}" updated.')),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteCustomTuning(TuningPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Custom Tuning?'),
        content: Text('Are you sure you want to delete "${preset.name}"?'),
        actions: [
          TextButton(
            key: const Key('cancel_delete_tuning_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_tuning_button'),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _customTuningStorage.deleteCustomTuning(preset.id);
      if (!mounted) return;
      setState(() {
        _customPresets.removeWhere((p) => p.id == preset.id);
        if (_selectedPreset.id == preset.id) {
          _selectedPreset = TuningPreset.standard;
          if (_pitchResult.isPitched) {
            _tuningResult = _tunerEngine.evaluate(
              pitchResult: _pitchResult,
              preset: _selectedPreset,
              referenceA4: _referenceA4,
            );
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Custom tuning "${preset.name}" deleted.')),
      );
    }
  }

  void _setReferenceA4(double freq) {
    final clamped = ReferenceFrequency.clamp(freq);
    final updatedSettings = _settings.copyWith(referenceA4: clamped);
    setState(() {
      _referenceA4 = clamped;
      _settings = updatedSettings;
      if (_pitchResult.isPitched) {
        _tuningResult = _tunerEngine.evaluate(
          pitchResult: _pitchResult,
          preset: _selectedPreset,
          referenceA4: clamped,
        );
      }
    });
    _settingsService.saveSettings(updatedSettings);
  }

  void _setTuningPreset(TuningPreset preset) {
    final updatedSettings = _settings.copyWith(lastSelectedTuningId: preset.id);
    setState(() {
      _selectedPreset = preset;
      _settings = updatedSettings;
      if (_pitchResult.isPitched) {
        _tuningResult = _tunerEngine.evaluate(
          pitchResult: _pitchResult,
          preset: preset,
          referenceA4: _referenceA4,
        );
      }
    });
    _settingsService.saveSettings(updatedSettings);
  }

  Future<void> _toggleFavorite(String presetId) async {
    final updated = _settings.toggleFavorite(presetId);
    setState(() {
      _settings = updated;
    });
    await _settingsService.saveSettings(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(
          updated.isFavorite(presetId)
              ? 'Added to favorites'
              : 'Removed from favorites',
        ),
      ),
    );
  }

  Future<void> _openTuningBottomSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF004382) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final favorites = _allPresets
                .where((p) => _settings.isFavorite(p.id))
                .toList();

            final displayPresets = _showFavoritesOnly ? favorites : _allPresets;

            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.35,
              maxChildSize: 0.88,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Drag Handle Pill
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFFDCF4A2).withValues(alpha: 0.3)
                            : Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Sheet Header with Title, Count, and + Custom Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tune,
                            color: Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select Tuning',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? const Color(0xFFDCF4A2)
                                        : const Color(0xFF1E202C),
                                  ),
                                ),
                                Text(
                                  '${_allPresets.length} tunings available',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? const Color(
                                            0xFFDCF4A2,
                                          ).withValues(alpha: 0.7)
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // "+ Custom" Action Button
                          FilledButton.tonalIcon(
                            key: const Key('create_custom_tuning_chip'),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text(
                              'Custom',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                            onPressed: () async {
                              Navigator.of(sheetContext).pop();
                              await _openCreateTuningDialog();
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 20,
                              color: isDark ? const Color(0xFFDCF4A2) : null,
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Favorites Filter Toggle Chip
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Row(
                        children: [
                          FilterChip(
                            key: const Key('favorites_filter_chip'),
                            avatar: Icon(
                              Icons.star,
                              size: 14,
                              color: _showFavoritesOnly
                                  ? Colors.amberAccent
                                  : (isDark
                                        ? const Color(
                                            0xFFDCF4A2,
                                          ).withValues(alpha: 0.7)
                                        : Colors.black54),
                            ),
                            label: Text(
                              'Favorites Only (${favorites.length})',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _showFavoritesOnly,
                            onSelected: (val) {
                              setSheetState(() {
                                _showFavoritesOnly = val;
                              });
                              setState(() {
                                _showFavoritesOnly = val;
                              });
                            },
                            visualDensity: VisualDensity.compact,
                            selectedColor: Colors.amber.withValues(alpha: 0.25),
                            checkmarkColor: Colors.amberAccent,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 18),

                    // List of Tunings
                    Expanded(
                      child: displayPresets.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_border,
                                    size: 40,
                                    color: isDark
                                        ? const Color(
                                            0xFFDCF4A2,
                                          ).withValues(alpha: 0.3)
                                        : Colors.black26,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No favorite tunings yet',
                                    style: TextStyle(
                                      color: isDark
                                          ? const Color(
                                              0xFFDCF4A2,
                                            ).withValues(alpha: 0.7)
                                          : Colors.black54,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 4.0,
                              ),
                              itemCount: displayPresets.length,
                              itemBuilder: (context, index) {
                                final preset = displayPresets[index];
                                final isSelected =
                                    preset.id == _selectedPreset.id;
                                final isFav = _settings.isFavorite(preset.id);
                                final formula = preset.strings
                                    .map((s) => s.noteName)
                                    .join('  •  ');

                                return Container(
                                  key: Key('preset_chip_${preset.id}'),
                                  margin: const EdgeInsets.only(bottom: 8.0),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primary.withValues(
                                            alpha: isDark ? 0.25 : 0.10,
                                          )
                                        : (isDark
                                              ? const Color(0xFF00376B)
                                              : Colors.black.withValues(
                                                  alpha: 0.02,
                                                )),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : (isDark
                                                ? const Color(0xFF0068C7)
                                                : const Color(0xFFE4E6F0)),
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      _setTuningPreset(preset);
                                      Navigator.of(sheetContext).pop();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14.0,
                                        vertical: 12.0,
                                      ),
                                      child: Row(
                                        children: [
                                          // Checkmark / Icon
                                          Icon(
                                            isSelected
                                                ? Icons.check_circle
                                                : (preset.isCustom
                                                      ? Icons.tune
                                                      : Icons
                                                            .music_note_outlined),
                                            color: isSelected
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : (isDark
                                                      ? const Color(
                                                          0xFFDCF4A2,
                                                        ).withValues(alpha: 0.6)
                                                      : Colors.black38),
                                            size: 22,
                                          ),
                                          const SizedBox(width: 12),

                                          // Preset Name & Formula
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        preset.name,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: isSelected
                                                              ? FontWeight.bold
                                                              : FontWeight.w600,
                                                          color: isSelected
                                                              ? (isDark
                                                                    ? const Color(
                                                                        0xFFDCF4A2,
                                                                      )
                                                                    : Theme.of(
                                                                        context,
                                                                      ).colorScheme.primary)
                                                              : (isDark
                                                                    ? const Color(
                                                                        0xFFDCF4A2,
                                                                      )
                                                                    : const Color(
                                                                        0xFF1E202C,
                                                                      )),
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (preset.isCustom) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 1,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors
                                                              .deepPurple
                                                              .withValues(
                                                                alpha: 0.3,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'CUSTOM',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors
                                                                .deepPurpleAccent,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  formula,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    letterSpacing: 1.1,
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFDCF4A2,
                                                          ).withValues(
                                                            alpha: 0.7,
                                                          )
                                                        : Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Active Badge
                                          if (isSelected) ...[
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: 0.25),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'ACTIVE',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                          ],

                                          // Favorite Star Toggle
                                          IconButton(
                                            key: Key('sheet_fav_${preset.id}'),
                                            icon: Icon(
                                              isFav
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: isFav
                                                  ? Colors.amberAccent
                                                  : (isDark
                                                        ? const Color(
                                                            0xFFDCF4A2,
                                                          ).withValues(
                                                            alpha: 0.4,
                                                          )
                                                        : Colors.black26),
                                              size: 20,
                                            ),
                                            tooltip: isFav
                                                ? 'Remove Favorite'
                                                : 'Add Favorite',
                                            onPressed: () async {
                                              await _toggleFavorite(preset.id);
                                              setSheetState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openSettingsDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.60),
      builder: (ctx) => SettingsDialog(
        currentSettings: _settings,
        allPresets: _allPresets,
        onSave: (newSettings) async {
          setState(() {
            _settings = newSettings;
            _referenceA4 = newSettings.referenceA4;
            _tunerEngine = _tunerEngine.copyWith(
              referenceA4: newSettings.referenceA4,
              inTuneToleranceCents: newSettings.inTuneToleranceCents,
            );
            if (_pitchResult.isPitched) {
              _tuningResult = _tunerEngine.evaluate(
                pitchResult: _pitchResult,
                preset: _selectedPreset,
                referenceA4: _referenceA4,
              );
            }
          });
          await _settingsService.saveSettings(newSettings);
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Preferences saved.')));
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isCapturing) {
        _stopCapture();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isCapturing = false;
    _audioCaptureService.stopCapture();
    if (widget.audioCaptureService == null) {
      _audioCaptureService.dispose();
    }
    super.dispose();
  }

  Future<void> _checkAndInit() async {
    setState(() {
      _isChecking = true;
    });

    final hasPerm = await widget.microphoneService.checkPermission();

    if (hasPerm) {
      await widget.microphoneService.initializeMicrophone();
    }

    if (!mounted) return;

    setState(() {
      _isChecking = false;
      _hasPermission = hasPerm;
    });
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isChecking = true;
    });

    final granted = await widget.microphoneService.requestPermission();

    if (granted) {
      await widget.microphoneService.initializeMicrophone();
    }

    if (!mounted) return;

    setState(() {
      _isChecking = false;
      _hasPermission = granted;
    });
  }

  Future<void> _startCapture() async {
    if (!_hasPermission) return;

    setState(() {
      _isCapturing = true;
      _captureError = null;
      _pitchResult = const PitchResult.unpitched();
      _tuningResult = const TuningResult.unpitched();
      _inTuneConsecutiveFrames = 0;
      _unpitchedConsecutiveFrames = 0;
      _hasPlayedInTuneSoundForCurrentNote = false;
    });

    try {
      await _audioCaptureService.startCapture(
        onAudioChunk: (Uint8List chunk) {
          if (!mounted) return;

          // Acoustic Echo & Resonance Blanking:
          // While success chime is sounding through the speaker, ignore microphone input
          // to prevent acoustic feedback loops and false pitch re-triggering.
          if (_audioFeedbackService.isPlaying) {
            return;
          }

          final rms = AudioCaptureService.calculateRms(chunk);

          // Acoustic Noise Gate: Silence/low ambient room noise is rejected before pitch evaluation
          final isAudible = rms >= 70.0;
          final pitch = isAudible
              ? _pitchDetector.detectPitch(chunk)
              : const PitchResult.unpitched();

          final tuning = isAudible && pitch.isPitched
              ? _tunerEngine.evaluate(
                  pitchResult: pitch,
                  preset: _selectedPreset,
                  referenceA4: _referenceA4,
                )
              : const TuningResult.unpitched();

          // In-Tune Audio Feedback State Machine:
          // Requires 2 consecutive in-tune frames (~90ms) before triggering sound,
          // which rejects isolated ambient room noise spikes while responding swiftly to real plucks.
          if (pitch.isPitched) {
            _unpitchedConsecutiveFrames = 0;
            if (tuning.status == TuningStatus.inTune) {
              _inTuneConsecutiveFrames++;
              if (_inTuneConsecutiveFrames >= 2 &&
                  !_hasPlayedInTuneSoundForCurrentNote) {
                _hasPlayedInTuneSoundForCurrentNote = true;
                if (_settings.hapticEnabled) {
                  HapticFeedback.selectionClick();
                }
                if (_settings.soundEnabled) {
                  _audioFeedbackService.playInTuneSound();
                }
              }
            } else {
              _inTuneConsecutiveFrames = 0;
              // Left in-tune range: Only re-arm if pitch moved substantially out of tune (> 6 cents)
              // for a genuine peg adjustment, preventing speaker harmonics from re-triggering!
              if (tuning.centsDifference.abs() > 6.0) {
                _hasPlayedInTuneSoundForCurrentNote = false;
              }
            }
          } else {
            _unpitchedConsecutiveFrames++;
            _inTuneConsecutiveFrames = 0;
            // Only re-arm after note has decayed into silence for at least ~600ms (14 frames)
            if (_unpitchedConsecutiveFrames >= 14) {
              _hasPlayedInTuneSoundForCurrentNote = false;
            }
          }

          final smoothedCents = _pitchStabilizer.update(tuning);

          setState(() {
            if (pitch.isPitched) {
              _pitchResult = pitch;
              _tuningResult = tuning;
              _visualCents = smoothedCents;
            } else if (_unpitchedConsecutiveFrames >= 2 || !isAudible) {
              _pitchResult = const PitchResult.unpitched();
              _tuningResult = const TuningResult.unpitched();
              _visualCents = 0.0;
              _pitchStabilizer.reset();
            }
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isCapturing = false;
            _captureError = error.toString();
            _visualCents = 0.0;
            _inTuneConsecutiveFrames = 0;
            _unpitchedConsecutiveFrames = 0;
            _hasPlayedInTuneSoundForCurrentNote = false;
            _pitchStabilizer.reset();
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _captureError = e.toString();
        _visualCents = 0.0;
        _inTuneConsecutiveFrames = 0;
        _unpitchedConsecutiveFrames = 0;
        _hasPlayedInTuneSoundForCurrentNote = false;
        _pitchStabilizer.reset();
      });
    }
  }

  Future<void> _stopCapture() async {
    _audioFeedbackService.reset();
    if (mounted) {
      setState(() {
        _isCapturing = false;
        _pitchResult = const PitchResult.unpitched();
        _tuningResult = const TuningResult.unpitched();
        _visualCents = 0.0;
        _inTuneConsecutiveFrames = 0;
        _unpitchedConsecutiveFrames = 0;
        _hasPlayedInTuneSoundForCurrentNote = false;
        _pitchStabilizer.reset();
      });
    }
    await _audioCaptureService.stopCapture();
  }

  Color _getStatusColor(TuningStatus status, bool isDark) {
    switch (status) {
      case TuningStatus.inTune:
        return isDark ? const Color(0xFFDCF4A2) : const Color(0xFF059669);
      case TuningStatus.flat:
        return isDark ? const Color(0xFFFFD54F) : const Color(0xFFD97706);
      case TuningStatus.sharp:
        return isDark ? const Color(0xFFFF7043) : const Color(0xFFDC2626);
      case TuningStatus.unpitched:
        return isDark
            ? const Color(0xFFDCF4A2).withValues(alpha: 0.7)
            : const Color(0xFF6B7280);
    }
  }

  String _getStatusText(TuningStatus status) {
    switch (status) {
      case TuningStatus.inTune:
        return 'IN TUNE';
      case TuningStatus.flat:
        return 'FLAT (Tune Up)';
      case TuningStatus.sharp:
        return 'SHARP (Tune Down)';
      case TuningStatus.unpitched:
        return 'LISTENING...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _isCapturing
        ? _getStatusColor(_tuningResult.status, isDark)
        : (isDark
              ? const Color(0xFFDCF4A2).withValues(alpha: 0.5)
              : const Color(0xFF6B7280));
    final statusText = _isCapturing
        ? _getStatusText(_tuningResult.status)
        : 'TUNER OFF';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDCF4A2).withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'lib/logo.png',
                  key: const Key('app_logo_image'),
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00376B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.graphic_eq,
                      color: Color(0xFFDCF4A2),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RESO HERTZ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    color: Color(0xFFDCF4A2),
                  ),
                ),
                Text(
                  'ACOUSTIC PRECISION TUNER',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: const Color(0xFFDCF4A2).withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('settings_button'),
            icon: const Icon(Icons.settings_outlined, color: Color(0xFFDCF4A2)),
            tooltip: 'Settings',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF0055A4),
          gradient: RadialGradient(
            center: Alignment(-1.0, -1.0),
            radius: 0.85,
            colors: [
              Color(0x3BDCF4A2), // Subtle lime yellow glow from top-left
              Color(0x14DCF4A2), // Soft fade past the logo icon
              Color(0xFF0055A4), // Deep signature French Blue
            ],
            stops: [0.0, 0.40, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: _isChecking
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_hasPermission) ...[
                          const Icon(
                            Icons.mic_off,
                            size: 56,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Microphone Permission Required',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Reso Hertz requires microphone access to tune your guitar offline.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _requestPermission,
                            icon: const Icon(Icons.mic),
                            label: const Text('Grant Permission'),
                          ),
                        ],
                        if (_hasPermission) ...[
                          // Standard Guitar Tuner Card with In-Tune Bloom Animation
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF004382)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    _tuningResult.status == TuningStatus.inTune
                                    ? statusColor
                                    : (isDark
                                          ? const Color(0xFF0068C7)
                                          : const Color(0xFFE4E6F0)),
                                width:
                                    _tuningResult.status == TuningStatus.inTune
                                    ? 2.5
                                    : 1.2,
                              ),
                              boxShadow: [
                                if (_tuningResult.status == TuningStatus.inTune)
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.35),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  )
                                else if (isDark)
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  )
                                else
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 20.0,
                                horizontal: 20.0,
                              ),
                              child: Column(
                                children: [
                                  // Tuning Preset & String Header with Quick Favorite Toggle
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          key: const Key('tuner_string_label'),
                                          _tuningResult.targetString != null
                                              ? _tuningResult
                                                    .targetString!
                                                    .fullLabel
                                              : _selectedPreset.fullTitle,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isDark
                                                ? const Color(0xFFDCF4A2)
                                                : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        key: const Key(
                                          'toggle_fav_active_preset',
                                        ),
                                        icon: Icon(
                                          _settings.isFavorite(
                                                _selectedPreset.id,
                                              )
                                              ? Icons.star
                                              : Icons.star_border,
                                          color:
                                              _settings.isFavorite(
                                                _selectedPreset.id,
                                              )
                                              ? Colors.amberAccent
                                              : (isDark
                                                    ? const Color(
                                                        0xFFDCF4A2,
                                                      ).withValues(alpha: 0.5)
                                                    : Colors.black38),
                                          size: 18,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        tooltip:
                                            _settings.isFavorite(
                                              _selectedPreset.id,
                                            )
                                            ? 'Remove from Favorites'
                                            : 'Add to Favorites',
                                        onPressed: () =>
                                            _toggleFavorite(_selectedPreset.id),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Single Tuning Icon Button that opens Material Bottom Sheet
                                  Center(
                                    child: Tooltip(
                                      message:
                                          'Select Tuning (${_selectedPreset.name})',
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          key: const Key(
                                            'open_tuning_sheet_button',
                                          ),
                                          onTap: _openTuningBottomSheet,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? const Color(0xFF00376B)
                                                  : Colors.black.withValues(
                                                      alpha: 0.05,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: isDark
                                                    ? const Color(0xFF0068C7)
                                                    : const Color(0xFFE4E6F0),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.tune,
                                                  key: const Key('tuning_icon'),
                                                  size: 16,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _selectedPreset.name,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFDCF4A2,
                                                          )
                                                        : const Color(
                                                            0xFF1E202C,
                                                          ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.keyboard_arrow_down,
                                                  size: 18,
                                                  color: isDark
                                                      ? const Color(
                                                          0xFFDCF4A2,
                                                        ).withValues(alpha: 0.7)
                                                      : Colors.black54,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_selectedPreset.isCustom) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF00376B)
                                            : Colors.deepPurple.withValues(
                                                alpha: 0.2,
                                              ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isDark
                                              ? const Color(0xFF0068C7)
                                              : Colors.deepPurpleAccent
                                                    .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.tune,
                                            size: 14,
                                            color: Colors.amberAccent,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Custom: ${_selectedPreset.name}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? const Color(0xFFDCF4A2)
                                                    : const Color(0xFF1E202C),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          TextButton.icon(
                                            key: const Key(
                                              'edit_custom_tuning_button',
                                            ),
                                            icon: const Icon(
                                              Icons.edit,
                                              size: 13,
                                            ),
                                            label: const Text(
                                              'Edit',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            style: TextButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () =>
                                                _openEditTuningDialog(
                                                  _selectedPreset,
                                                ),
                                          ),
                                          TextButton.icon(
                                            key: const Key(
                                              'delete_custom_tuning_button',
                                            ),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 13,
                                              color: Colors.redAccent,
                                            ),
                                            label: const Text(
                                              'Delete',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () =>
                                                _confirmDeleteCustomTuning(
                                                  _selectedPreset,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  // Reference Pitch Calibration Selector
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF00376B)
                                          : Colors.black.withValues(
                                              alpha: 0.03,
                                            ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF0068C7)
                                            : const Color(0xFFE4E6F0),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            // A4 Pitch Display
                                            Text(
                                              key: const Key(
                                                'ref_freq_display',
                                              ),
                                              'A4 = ${ReferenceFrequency.format(_referenceA4)}',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: isDark
                                                    ? const Color(0xFFDCF4A2)
                                                    : const Color(0xFF1E202C),
                                              ),
                                            ),
                                            // Preset chips: 432, 440, 442
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: ReferenceFrequency.commonPresets.map((
                                                preset,
                                              ) {
                                                final isSelected =
                                                    (_referenceA4 - preset)
                                                        .abs() <
                                                    0.01;
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 4.0,
                                                      ),
                                                  child: ChoiceChip(
                                                    key: Key(
                                                      'ref_freq_${preset.toInt()}',
                                                    ),
                                                    label: Text(
                                                      '${preset.toInt()}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: isSelected
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                        color: isSelected
                                                            ? (isDark
                                                                  ? const Color(
                                                                      0xFF00376B,
                                                                    )
                                                                  : Colors
                                                                        .white)
                                                            : (isDark
                                                                  ? const Color(
                                                                      0xFFDCF4A2,
                                                                    )
                                                                  : Colors
                                                                        .black87),
                                                      ),
                                                    ),
                                                    selected: isSelected,
                                                    onSelected: (_) =>
                                                        _setReferenceA4(preset),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                        ),
                                                    selectedColor: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                    backgroundColor: isDark
                                                        ? const Color(
                                                            0xFF004382,
                                                          )
                                                        : null,
                                                    showCheckmark: false,
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // Reference Frequency Slider
                                        Row(
                                          children: [
                                            Text(
                                              '${ReferenceFrequency.minAllowed.toInt()}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? const Color(
                                                        0xFFDCF4A2,
                                                      ).withValues(alpha: 0.6)
                                                    : Colors.black38,
                                              ),
                                            ),
                                            Expanded(
                                              child: SliderTheme(
                                                data: SliderTheme.of(context).copyWith(
                                                  trackHeight: 3,
                                                  thumbShape:
                                                      const RoundSliderThumbShape(
                                                        enabledThumbRadius: 7,
                                                      ),
                                                  overlayShape:
                                                      const RoundSliderOverlayShape(
                                                        overlayRadius: 14,
                                                      ),
                                                ),
                                                child: Slider(
                                                  key: const Key(
                                                    'ref_freq_slider',
                                                  ),
                                                  value: _referenceA4.clamp(
                                                    ReferenceFrequency
                                                        .minAllowed,
                                                    ReferenceFrequency
                                                        .maxAllowed,
                                                  ),
                                                  min: ReferenceFrequency
                                                      .minAllowed,
                                                  max: ReferenceFrequency
                                                      .maxAllowed,
                                                  divisions:
                                                      (ReferenceFrequency
                                                                  .maxAllowed -
                                                              ReferenceFrequency
                                                                  .minAllowed)
                                                          .toInt(),
                                                  label:
                                                      ReferenceFrequency.format(
                                                        _referenceA4,
                                                      ),
                                                  activeColor: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                  inactiveColor: isDark
                                                      ? const Color(0xFF0068C7)
                                                      : Colors.black12,
                                                  onChanged: (double value) {
                                                    _setReferenceA4(
                                                      value.roundToDouble(),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${ReferenceFrequency.maxAllowed.toInt()}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? const Color(
                                                        0xFFDCF4A2,
                                                      ).withValues(alpha: 0.6)
                                                    : Colors.black38,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // 6-String Headstock Visualizer
                                  Container(
                                    key: const Key(
                                      'guitar_headstock_visualizer',
                                    ),
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF00376B)
                                          : Colors.black.withValues(
                                              alpha: 0.04,
                                            ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF0068C7)
                                            : Colors.black12,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: _selectedPreset.strings.map((
                                        guitarString,
                                      ) {
                                        final isCurrentTarget =
                                            _tuningResult.targetString !=
                                                null &&
                                            _tuningResult
                                                    .targetString!
                                                    .stringNumber ==
                                                guitarString.stringNumber;
                                        final stringColor = isCurrentTarget
                                            ? statusColor
                                            : (isDark
                                                  ? const Color(
                                                      0xFFDCF4A2,
                                                    ).withValues(alpha: 0.8)
                                                  : Colors.black54);
                                        final activeBg = isCurrentTarget
                                            ? statusColor.withValues(
                                                alpha: isDark ? 0.22 : 0.15,
                                              )
                                            : Colors.transparent;

                                        return AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          curve: Curves.easeOut,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: activeBg,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: isCurrentTarget
                                                  ? statusColor
                                                  : (isDark
                                                        ? const Color(
                                                            0xFF0068C7,
                                                          )
                                                        : Colors.black12),
                                              width: isCurrentTarget
                                                  ? 1.8
                                                  : 1.0,
                                            ),
                                            boxShadow: isCurrentTarget
                                                ? [
                                                    BoxShadow(
                                                      color: statusColor
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      blurRadius: 8,
                                                      spreadRadius: 1,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '#${guitarString.stringNumber}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: isCurrentTarget
                                                      ? statusColor
                                                      : (isDark
                                                            ? const Color(
                                                                0xFFDCF4A2,
                                                              ).withValues(
                                                                alpha: 0.5,
                                                              )
                                                            : Colors.black38),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${guitarString.noteName}${guitarString.octave}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: isCurrentTarget
                                                      ? FontWeight.bold
                                                      : FontWeight.w600,
                                                  color: stringColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Big Note Display
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        key: const Key('note_name_display'),
                                        _tuningResult.targetString
                                                ?.formattedNoteName(
                                                  preferSharps:
                                                      !_settings.preferFlats,
                                                ) ??
                                            '--',
                                        style: TextStyle(
                                          fontSize: 68,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                          letterSpacing: 2,
                                          shadows: [
                                            if (_tuningResult.status ==
                                                TuningStatus.inTune)
                                              Shadow(
                                                color: statusColor.withValues(
                                                  alpha: 0.5,
                                                ),
                                                blurRadius: 16,
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (_tuningResult.targetString != null)
                                        Text(
                                          key: const Key('note_octave_display'),
                                          '${_tuningResult.targetString!.octave}',
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Status Badge with Directional Micro-Icon
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    key: const Key('tuning_status_badge'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(
                                        alpha: isDark ? 0.18 : 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: statusColor.withValues(
                                          alpha: 0.7,
                                        ),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        if (_tuningResult.status ==
                                            TuningStatus.inTune)
                                          BoxShadow(
                                            color: statusColor.withValues(
                                              alpha: 0.35,
                                            ),
                                            blurRadius: 10,
                                            spreadRadius: 1,
                                          ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_tuningResult.status ==
                                            TuningStatus.inTune) ...[
                                          Icon(
                                            Icons.check_circle,
                                            size: 16,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 6),
                                        ] else if (_tuningResult.status ==
                                            TuningStatus.flat) ...[
                                          Icon(
                                            Icons.arrow_upward,
                                            size: 16,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 6),
                                        ] else if (_tuningResult.status ==
                                            TuningStatus.sharp) ...[
                                          Icon(
                                            Icons.arrow_downward,
                                            size: 16,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          statusText,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Horizontal Tuning Scale with Guitar-Pick Location Marker
                                  HorizontalTuningScale(
                                    stabilizedCents: _visualCents,
                                    isPitched: _tuningResult.isPitched,
                                    status: _tuningResult.status,
                                    statusColor: statusColor,
                                    isDark: isDark,
                                  ),
                                  const SizedBox(height: 12),
                                  // Cents & Frequency Numerical Details
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        key: const Key('cents_display'),
                                        _tuningResult.isPitched
                                            ? '${_tuningResult.centsDifference >= 0 ? '+' : ''}${_tuningResult.centsDifference.toStringAsFixed(1)} cents'
                                            : '-- cents',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                      ),
                                      Text(
                                        key: const Key('frequency_comparison'),
                                        _tuningResult.isPitched
                                            ? '${_tuningResult.detectedFrequency.toStringAsFixed(1)} / ${_tuningResult.targetFrequency.toStringAsFixed(1)} Hz'
                                            : '-- / -- Hz',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark
                                              ? const Color(
                                                  0xFFDCF4A2,
                                                ).withValues(alpha: 0.85)
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Raw Pitch Diagnostics
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        key: const Key('frequency_display'),
                                        _pitchResult.isPitched
                                            ? '${_pitchResult.frequency.toStringAsFixed(1)} Hz'
                                            : (_isCapturing
                                                  ? 'Listening...'
                                                  : '-- Hz'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? const Color(
                                                  0xFFDCF4A2,
                                                ).withValues(alpha: 0.6)
                                              : Colors.black38,
                                        ),
                                      ),
                                      Text(
                                        key: const Key('confidence_display'),
                                        _pitchResult.isPitched
                                            ? 'Confidence: ${(_pitchResult.confidence * 100).toStringAsFixed(0)}%'
                                            : 'Confidence: --%',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? const Color(
                                                  0xFFDCF4A2,
                                                ).withValues(alpha: 0.6)
                                              : Colors.black38,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Minimalist Circular Microphone Toggle Button
                          Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _isCapturing
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFFEF4444),
                                          Color(0xFFDC2626),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : LinearGradient(
                                        colors: isDark
                                            ? const [
                                                Color(0xFFDCF4A2),
                                                Color(0xFFC5E880),
                                              ]
                                            : [
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                const Color(0xFF06D6A0),
                                              ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_isCapturing
                                                ? const Color(0xFFEF4444)
                                                : (isDark
                                                      ? const Color(0xFFDCF4A2)
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.primary))
                                            .withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: IconButton(
                                key: _isCapturing
                                    ? const Key('stop_capture_button')
                                    : const Key('start_capture_button'),
                                iconSize: 32,
                                icon: Icon(
                                  _isCapturing
                                      ? Icons.mic_rounded
                                      : Icons.mic_off_rounded,
                                  color: _isCapturing
                                      ? Colors.white
                                      : (isDark
                                            ? const Color(0xFF00376B)
                                            : Colors.white),
                                ),
                                tooltip: _isCapturing
                                    ? 'Stop Listening'
                                    : 'Start Listening',
                                onPressed: _isCapturing
                                    ? _stopCapture
                                    : _startCapture,
                              ),
                            ),
                          ),
                          if (_captureError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Error: $_captureError',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
