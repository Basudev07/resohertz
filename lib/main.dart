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
import 'package:resohertz/tuner/circular_knob_tuner.dart';
import 'package:resohertz/tuner/pitch_stabilizer.dart';
import 'package:resohertz/tuner/tuner_engine.dart';
import 'package:resohertz/tuner/tuning_result.dart';
import 'package:resohertz/tuning/custom_tuning_dialog.dart';
import 'package:resohertz/tuning/custom_tuning_storage.dart';
import 'package:resohertz/tuning/reference_frequency.dart';
import 'package:resohertz/tuning/tuning_preset.dart';
import 'package:resohertz/ui/aurora_mesh_background.dart';

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
  int? _candidateStringNumber;
  int _candidateStringFrames = 0;
  int _idlePitchedFrames = 0;
  bool _isModalOpen = false;
  int _transposeSemitones = 0;
  double _referenceA4 = ReferenceFrequency.standard;
  TuningPreset _selectedPreset = TuningPreset.standard;
  String? _captureError;

  TuningPreset get _effectivePreset => _transposeSemitones == 0
      ? _selectedPreset
      : _selectedPreset.transpose(
          _transposeSemitones,
          preferFlats: _settings.preferFlats,
        );

  void _setTransposeSemitones(int semitones) {
    HapticFeedback.selectionClick();
    final clamped = semitones.clamp(-6, 6);
    setState(() {
      _transposeSemitones = clamped;
      _settings = _settings.copyWith(transposeSemitones: clamped);
      if (_pitchResult.isPitched) {
        _tuningResult = _tunerEngine.evaluate(
          pitchResult: _pitchResult,
          preset: _effectivePreset,
          referenceA4: _referenceA4,
        );
      }
    });
    _settingsService.saveSettings(
      _settings.copyWith(transposeSemitones: clamped),
    );
  }

  String _getTransposeLabel(int semitones) {
    if (semitones == 0) {
      return 'Standard Pitch (±0)';
    }
    final abs = semitones.abs();
    final stepWord = abs == 1 ? 'Half-Step' : 'Half-Steps';
    if (semitones < 0) {
      return '-$abs $stepWord Down (-${abs * 100}¢)';
    } else {
      return '+$abs $stepWord Up (Capo $abs / +${abs * 100}¢)';
    }
  }

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
    _transposeSemitones = _settings.transposeSemitones;
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
      _transposeSemitones = settings.transposeSemitones;
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
                preset: _effectivePreset,
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
                  preset: _effectivePreset,
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
              preset: _effectivePreset,
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
          preset: _effectivePreset,
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
          preset: _effectivePreset,
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
    final isAurora = _settings.backgroundStyle == 'aurora';
    final sheetBg = isDark
        ? (isAurora ? const Color(0xFF131524) : const Color(0xFF004382))
        : Colors.white;
    final sheetAccent = isDark
        ? (isAurora ? const Color(0xFF37E7FF) : const Color(0xFFDCF4A2))
        : Theme.of(context).colorScheme.primary;

    final itemBg = isDark
        ? (isAurora ? const Color(0xFF1B1E32) : const Color(0xFF00376B))
        : Colors.black.withValues(alpha: 0.02);
    final itemBorder = isDark
        ? (isAurora ? const Color(0xFF282D4A) : const Color(0xFF0068C7))
        : const Color(0xFFE4E6F0);

    _isModalOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: sheetBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return RepaintBoundary(
            child: StatefulBuilder(
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
                            ? sheetAccent.withValues(alpha: 0.35)
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
                            color: sheetAccent,
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
                                        ? sheetAccent
                                        : const Color(0xFF1E202C),
                                  ),
                                ),
                                Text(
                                  '${_allPresets.length} tunings available',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? sheetAccent.withValues(alpha: 0.7)
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
                              color: isDark ? sheetAccent : null,
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
                                        ? sheetAccent.withValues(alpha: 0.7)
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
                    const SizedBox(height: 10),

                    // Transpose Half-Step Adjustment Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14.0,
                          vertical: 10.0,
                        ),
                        decoration: BoxDecoration(
                          color: itemBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _transposeSemitones != 0
                                ? sheetAccent.withValues(alpha: 0.60)
                                : itemBorder,
                            width: _transposeSemitones != 0 ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.swap_vert,
                                  size: 16,
                                  color: sheetAccent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'TRANSPOSE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                    color: isDark
                                        ? sheetAccent
                                        : const Color(0xFF1E202C),
                                  ),
                                ),
                                const Spacer(),
                                if (_transposeSemitones != 0)
                                  GestureDetector(
                                    key: const Key('transpose_reset_button'),
                                    onTap: () {
                                      _setTransposeSemitones(0);
                                      setSheetState(() {});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: sheetAccent.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'RESET (0)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: sheetAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                // -1 Half Step Button
                                OutlinedButton(
                                  key: const Key('transpose_down_button'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: const Size(48, 36),
                                    side: BorderSide(
                                      color: _transposeSemitones > -6
                                          ? sheetAccent.withValues(alpha: 0.6)
                                          : (isDark
                                                ? Colors.white12
                                                : Colors.black12),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: _transposeSemitones > -6
                                      ? () {
                                          _setTransposeSemitones(
                                            _transposeSemitones - 1,
                                          );
                                          setSheetState(() {});
                                        }
                                      : null,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.remove,
                                        size: 14,
                                        color: _transposeSemitones > -6
                                            ? sheetAccent
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '½',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: _transposeSemitones > -6
                                              ? sheetAccent
                                              : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Transpose Info Display
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _getTransposeLabel(_transposeSemitones),
                                          key: const Key(
                                            'transpose_display_text',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _transposeSemitones != 0
                                                ? sheetAccent
                                                : (isDark
                                                      ? Colors.white70
                                                      : Colors.black87),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _effectivePreset.notesSummary,
                                          key: const Key(
                                            'transpose_notes_preview',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            letterSpacing: 1.1,
                                            fontWeight: FontWeight.w500,
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.black45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // +1 Half Step Button
                                OutlinedButton(
                                  key: const Key('transpose_up_button'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: const Size(48, 36),
                                    side: BorderSide(
                                      color: _transposeSemitones < 6
                                          ? sheetAccent.withValues(alpha: 0.6)
                                          : (isDark
                                                ? Colors.white12
                                                : Colors.black12),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: _transposeSemitones < 6
                                      ? () {
                                          _setTransposeSemitones(
                                            _transposeSemitones + 1,
                                          );
                                          setSheetState(() {});
                                        }
                                      : null,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add,
                                        size: 14,
                                        color: _transposeSemitones < 6
                                            ? sheetAccent
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '½',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: _transposeSemitones < 6
                                              ? sheetAccent
                                              : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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
                                        ? sheetAccent.withValues(alpha: 0.3)
                                        : Colors.black26,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No favorite tunings yet',
                                    style: TextStyle(
                                      color: isDark
                                          ? sheetAccent.withValues(alpha: 0.7)
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
                                final effectivePresetItem = _transposeSemitones == 0
                                    ? preset
                                    : preset.transpose(
                                        _transposeSemitones,
                                        preferFlats: _settings.preferFlats,
                                      );
                                final formula = effectivePresetItem.strings
                                    .map((s) => s.noteName)
                                    .join('  •  ');

                                return Container(
                                  key: Key('preset_chip_${preset.id}'),
                                  margin: const EdgeInsets.only(bottom: 8.0),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? sheetAccent.withValues(
                                            alpha: isDark ? 0.20 : 0.10,
                                          )
                                        : itemBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected ? sheetAccent : itemBorder,
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
                                                ? sheetAccent
                                                : (isDark
                                                      ? (isAurora
                                                            ? Colors.white54
                                                            : sheetAccent.withValues(alpha: 0.6))
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
                                                        _transposeSemitones == 0
                                                            ? preset.name
                                                            : '${preset.name} (${_transposeSemitones > 0 ? "+$_transposeSemitones" : "$_transposeSemitones"}½)',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: isSelected
                                                              ? FontWeight.bold
                                                              : FontWeight.w600,
                                                          color: isSelected
                                                              ? (isDark
                                                                    ? sheetAccent
                                                                    : Theme.of(
                                                                        context,
                                                                      ).colorScheme.primary)
                                                              : (isDark
                                                                    ? (isAurora
                                                                          ? Colors.white
                                                                          : const Color(0xFFDCF4A2))
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
                                                        ? (isAurora
                                                              ? Colors.white70
                                                              : sheetAccent.withValues(alpha: 0.7))
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
                                                color: sheetAccent.withValues(alpha: 0.20),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'ACTIVE',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: sheetAccent,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
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
                                                        ? sheetAccent
                                                            .withValues(
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
        ),
      );
    },
  );
    } finally {
      if (mounted) {
        setState(() {
          _isModalOpen = false;
        });
      }
    }
  }

  Future<void> _openSettingsDialog() async {
    _isModalOpen = true;
    try {
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
              _transposeSemitones = newSettings.transposeSemitones;
              _tunerEngine = _tunerEngine.copyWith(
                referenceA4: newSettings.referenceA4,
                inTuneToleranceCents: newSettings.inTuneToleranceCents,
              );
              if (_pitchResult.isPitched) {
                _tuningResult = _tunerEngine.evaluate(
                  pitchResult: _pitchResult,
                  preset: _effectivePreset,
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
    } finally {
      if (mounted) {
        setState(() {
          _isModalOpen = false;
        });
      }
    }
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
      _candidateStringNumber = null;
      _candidateStringFrames = 0;
      _idlePitchedFrames = 0;
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
          final isAudible = rms >= 80.0;
          final pitch = isAudible
              ? _pitchDetector.detectPitch(chunk)
              : const PitchResult.unpitched();

          final tuning = isAudible && pitch.isPitched
              ? _tunerEngine.evaluate(
                  pitchResult: pitch,
                  preset: _effectivePreset,
                  referenceA4: _referenceA4,
                  previousStatus: _tuningResult.status,
                )
              : const TuningResult.unpitched();

          // Transient Rejection & String Tracking:
          // 1. Waking up from Idle:
          //    A genuine guitar pluck resonates over many frames (> 500ms).
          //    A physical tap (screen tap, table knock, pocket rustle) is a transient impulse
          //    lasting < 30ms that vanishes after a single 46ms frame.
          //    We require 2 consecutive pitched frames of the same note to wake from idle,
          //    unless the sound is an exceptionally clean tone (confidence >= 0.90).
          // 2. Active Note:
          //    If an active note is already being tracked, an outlier jump to a different string
          //    requires 2 consecutive frames to switch, preventing pick scrape glitches.
          final TuningResult effectiveTuning;
          if (!_pitchStabilizer.hasValue) {
            if (tuning.isPitched) {
              if (tuning.confidence >= 0.90) {
                // High confidence pure musical tone: wake up immediately
                _idlePitchedFrames = 0;
                effectiveTuning = tuning;
              } else {
                final incomingStringNum = tuning.targetString?.stringNumber;
                if (_candidateStringNumber == incomingStringNum) {
                  _idlePitchedFrames++;
                } else {
                  _candidateStringNumber = incomingStringNum;
                  _idlePitchedFrames = 1;
                }

                if (_idlePitchedFrames >= 2) {
                  effectiveTuning = tuning;
                  _candidateStringNumber = null;
                  _idlePitchedFrames = 0;
                } else {
                  // Single frame candidate from idle: hold idle until confirmed
                  effectiveTuning = const TuningResult.unpitched();
                }
              }
            } else {
              _candidateStringNumber = null;
              _idlePitchedFrames = 0;
              effectiveTuning = const TuningResult.unpitched();
            }
          } else if (tuning.isPitched &&
              _pitchStabilizer.lastReliableResult?.targetString != null &&
              tuning.targetString != null &&
              tuning.targetString!.stringNumber !=
                  _pitchStabilizer
                      .lastReliableResult!
                      .targetString!
                      .stringNumber) {
            final incomingStringNum = tuning.targetString!.stringNumber;
            if (_candidateStringNumber == incomingStringNum) {
              _candidateStringFrames++;
            } else {
              _candidateStringNumber = incomingStringNum;
              _candidateStringFrames = 1;
            }

            final isConfirmedStringChange = _candidateStringFrames >= 2;

            if (isConfirmedStringChange) {
              effectiveTuning = tuning;
              _candidateStringNumber = null;
              _candidateStringFrames = 0;
            } else {
              // Transient pick scrape or harmonic outlier: hold the last reliable note rather than jumping strings
              effectiveTuning = _pitchStabilizer.lastReliableResult!;
            }
          } else {
            _candidateStringNumber = null;
            _candidateStringFrames = 0;
            effectiveTuning = tuning;
          }

          final smoothedCents = _pitchStabilizer.update(effectiveTuning);

          // In-Tune Audio Feedback State Machine:
          // Requires 2 consecutive in-tune frames (~90ms stability window) before triggering sound,
          // which rejects isolated ambient room noise spikes while responding swiftly to real plucks.
          if (effectiveTuning.isPitched) {
            _unpitchedConsecutiveFrames = 0;
            if (effectiveTuning.status == TuningStatus.inTune) {
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
              // Left in-tune range: Re-arm once pitch moves outside tolerance + hysteresis
              final rearmThreshold = _settings.inTuneToleranceCents + 0.25;
              if (effectiveTuning.centsDifference.abs() > rearmThreshold) {
                _hasPlayedInTuneSoundForCurrentNote = false;
              }
            }
          } else {
            _unpitchedConsecutiveFrames++;
            _inTuneConsecutiveFrames = 0;
            // Only re-arm after note has decayed into silence for at least ~500ms (11 frames)
            if (_unpitchedConsecutiveFrames >= 11) {
              _hasPlayedInTuneSoundForCurrentNote = false;
            }
          }

          if (_isModalOpen) {
            // While modal sheet or settings dialog is open, update tuner state silently
            // without triggering background screen rebuilds, ensuring smooth 60/120Hz sheet animations
            if (effectiveTuning.isPitched) {
              _pitchResult = pitch;
              _tuningResult = effectiveTuning;
              _visualCents = smoothedCents;
            } else if (_pitchStabilizer.isHolding &&
                _pitchStabilizer.lastReliableResult != null) {
              _tuningResult = _pitchStabilizer.lastReliableResult!;
              _visualCents = smoothedCents;
            } else {
              _pitchResult = const PitchResult.unpitched();
              _tuningResult = const TuningResult.unpitched();
              _visualCents = 0.0;
              _pitchStabilizer.reset();
            }
            return;
          }

          setState(() {
            if (effectiveTuning.isPitched) {
              _pitchResult = pitch;
              _tuningResult = effectiveTuning;
              _visualCents = smoothedCents;
            } else if (_pitchStabilizer.isHolding &&
                _pitchStabilizer.lastReliableResult != null) {
              // String decay hold period (~300ms): keep the last reliable note and string,
              // and hold the visual indicator smoothly instead of instantly collapsing to 0.
              _tuningResult = _pitchStabilizer.lastReliableResult!;
              _visualCents = smoothedCents;
            } else {
              // Hold period expired or tuner is idle: return cleanly to unpitched state
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
            _candidateStringNumber = null;
            _candidateStringFrames = 0;
            _idlePitchedFrames = 0;
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
        _candidateStringNumber = null;
        _candidateStringFrames = 0;
        _idlePitchedFrames = 0;
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
        _candidateStringNumber = null;
        _candidateStringFrames = 0;
        _idlePitchedFrames = 0;
        _hasPlayedInTuneSoundForCurrentNote = false;
        _pitchStabilizer.reset();
      });
    }
    await _audioCaptureService.stopCapture();
  }

  void _toggleCapture() {
    HapticFeedback.selectionClick();
    if (_isCapturing) {
      _stopCapture();
    } else {
      _startCapture();
    }
  }

  Color _getStatusColor(TuningStatus status, bool isDark) {
    final isAurora = _settings.backgroundStyle == 'aurora';
    switch (status) {
      case TuningStatus.inTune:
        return isDark
            ? (isAurora ? const Color(0xFF00FFB2) : const Color(0xFFDCF4A2))
            : const Color(0xFF059669);
      case TuningStatus.flat:
        return isDark ? const Color(0xFFFFD54F) : const Color(0xFFD97706);
      case TuningStatus.sharp:
        return isDark ? const Color(0xFFFF7043) : const Color(0xFFDC2626);
      case TuningStatus.unpitched:
        return isDark
            ? (isAurora ? const Color(0xFF37E7FF) : const Color(0xFFDCF4A2))
                .withValues(alpha: 0.7)
            : const Color(0xFF6B7280);
    }
  }

  String _getStatusTitle(TuningStatus status) {
    switch (status) {
      case TuningStatus.inTune:
        return 'IN TUNE';
      case TuningStatus.flat:
        return 'FLAT';
      case TuningStatus.sharp:
        return 'SHARP';
      case TuningStatus.unpitched:
        return 'LISTENING...';
    }
  }

  String? _getStatusInstruction(TuningStatus status) {
    switch (status) {
      case TuningStatus.inTune:
        return null;
      case TuningStatus.flat:
        return '(Tune Up)';
      case TuningStatus.sharp:
        return '(Tune Down)';
      case TuningStatus.unpitched:
        return 'Pluck string • Tap to stop';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAurora = _settings.backgroundStyle == 'aurora';
    final themeAccent = isDark
        ? (isAurora ? const Color(0xFF37E7FF) : const Color(0xFFDCF4A2))
        : (isAurora ? const Color(0xFF007A99) : const Color(0xFF0055A4));
    final containerBg = isDark
        ? (isAurora ? const Color(0xFF141829) : const Color(0xFF00376B))
        : Colors.black.withValues(alpha: 0.04);
    final containerBorder = isDark
        ? (isAurora ? const Color(0xFF262C46) : const Color(0xFF0068C7))
        : const Color(0xFFE4E6F0);

    final statusColor = _isCapturing
        ? _getStatusColor(_tuningResult.status, isDark)
        : (isDark
              ? themeAccent.withValues(alpha: 0.5)
              : const Color(0xFF6B7280));
    final statusTitle = _isCapturing
        ? _getStatusTitle(_tuningResult.status)
        : 'TUNER OFF';
    final statusInstruction = _isCapturing
        ? _getStatusInstruction(_tuningResult.status)
        : 'Tap knob to turn on';

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
                    color: themeAccent.withValues(alpha: 0.35),
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
                      color: containerBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.graphic_eq,
                      color: themeAccent,
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
                Text(
                  'RESO HERTZ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    color: themeAccent,
                  ),
                ),
                Text(
                  'ACOUSTIC PRECISION TUNER',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: themeAccent.withValues(alpha: 0.7),
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
            icon: Icon(Icons.settings_outlined, color: themeAccent),
            tooltip: 'Settings',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background layer: Default is Classic French Blue with lime glow;
          // can be switched to Chromatic Aurora in Settings
          if (isAurora)
            const RepaintBoundary(
              child: AuroraMeshBackground(),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
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
            ),
          SafeArea(
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
                          // Standard Guitar Tuner Card with Ramped Fade into Background
                          CustomPaint(
                            painter: RampedCardPainter(
                              cardColor: isDark
                                  ? (isAurora
                                      ? const Color(0xFF131522).withValues(alpha: 0.85)
                                      : const Color(0xFF004382))
                                  : Colors.white,
                              borderColor:
                                  _tuningResult.status == TuningStatus.inTune
                                  ? statusColor
                                  : (isDark
                                        ? (isAurora
                                            ? const Color(0xFF282D47).withValues(alpha: 0.70)
                                            : const Color(0xFF0068C7))
                                        : const Color(0xFFE4E6F0)),
                              borderWidth:
                                  _tuningResult.status == TuningStatus.inTune
                                  ? 2.5
                                  : 1.2,
                              isInTune:
                                  _tuningResult.status == TuningStatus.inTune,
                              inTuneGlowColor: statusColor,
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
                                                : _effectivePreset.fullTitle,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isDark
                                                ? themeAccent
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
                                                    ? themeAccent.withValues(alpha: 0.5)
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
                                              color: containerBg,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: containerBorder,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.tune,
                                                  key: const Key('tuning_icon'),
                                                  size: 16,
                                                  color: themeAccent,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _selectedPreset.name,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDark
                                                        ? themeAccent
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
                                                      ? themeAccent.withValues(alpha: 0.7)
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
                                        color: containerBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: containerBorder,
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
                                                    ? themeAccent
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
                                              foregroundColor: themeAccent,
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
                                      color: containerBg,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: containerBorder,
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
                                                    ? themeAccent
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
                                                                  ? (isAurora
                                                                        ? const Color(0xFF0D101D)
                                                                        : const Color(0xFF00376B))
                                                                  : Colors
                                                                        .white)
                                                            : (isDark
                                                                  ? themeAccent
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
                                                    selectedColor: themeAccent,
                                                    backgroundColor: isDark
                                                        ? (isAurora
                                                              ? const Color(0xFF20263E)
                                                              : const Color(0xFF004382))
                                                        : null,
                                                    side: BorderSide(
                                                      color: isSelected
                                                          ? themeAccent
                                                          : containerBorder,
                                                      width: isSelected ? 1.4 : 1.0,
                                                    ),
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
                                                    ? themeAccent.withValues(
                                                        alpha: 0.6,
                                                      )
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
                                                  activeColor: themeAccent,
                                                  inactiveColor: isDark
                                                      ? containerBorder
                                                      : Colors.black12,
                                                  thumbColor: themeAccent,
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
                                                    ? themeAccent.withValues(
                                                        alpha: 0.6,
                                                      )
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
                                      children: _effectivePreset.strings.map((
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
                                                  ? themeAccent.withValues(
                                                      alpha: 0.85,
                                                    )
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
                                                        ? containerBorder
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
                                                            ? themeAccent.withValues(
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
                                  const SizedBox(height: 28),
                                  // Modern Circular Knob (Dial) Tuner Visualizer
                                  CircularKnobTuner(
                                    stabilizedCents: _visualCents,
                                    isPitched: _tuningResult.isPitched,
                                    status: _tuningResult.status,
                                    statusColor: statusColor,
                                    isDark: isDark,
                                    isAurora: isAurora,
                                    noteName:
                                        _tuningResult.targetString
                                            ?.formattedNoteName(
                                              preferSharps:
                                                  !_settings.preferFlats,
                                            ) ??
                                        '--',
                                    noteOctave:
                                        _tuningResult.targetString != null
                                        ? '${_tuningResult.targetString!.octave}'
                                        : '',
                                    statusTitle: statusTitle,
                                    statusInstruction: statusInstruction,
                                    size: 272.0,
                                    onTap: _toggleCapture,
                                    tapKey: _isCapturing
                                        ? const Key('stop_capture_button')
                                        : const Key('start_capture_button'),
                                    isCapturing: _isCapturing,
                                  ),
                                  const SizedBox(height: 20),
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
                                              ? themeAccent.withValues(
                                                  alpha: 0.85,
                                                )
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
                                              ? themeAccent.withValues(
                                                  alpha: 0.6,
                                                )
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
                                              ? themeAccent.withValues(
                                                  alpha: 0.6,
                                                )
                                              : Colors.black38,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
        ],
      ),
    );
  }
}

/// Custom painter for the tuner card that smoothly blends and fades the card
/// surface and border into the background like a gradient ramp.
class RampedCardPainter extends CustomPainter {
  final Color cardColor;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final bool isInTune;
  final Color inTuneGlowColor;

  const RampedCardPainter({
    required this.cardColor,
    required this.borderColor,
    this.borderWidth = 1.2,
    this.borderRadius = 20.0,
    this.isInTune = false,
    required this.inTuneGlowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // In-tune bloom glow (only at top, fading out to transparent)
    if (isInTune) {
      final glowPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            inTuneGlowColor.withValues(alpha: 0.35),
            inTuneGlowColor.withValues(alpha: 0.15),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 0.85],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawRRect(rrect, glowPaint);
    }
    // Note: No black drop shadow is drawn, so the bottom blends seamlessly
    // into the background with zero dark outline or shadow artifacts.

    // 1. Background Fill with Smooth Progressive Ramp to 0 Opacity:
    // Starts solid at the top, progressively blends across the middle,
    // and completely dissolves into 0 opacity (transparent) at the bottom.
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          cardColor,
          cardColor.withValues(alpha: 0.85),
          cardColor.withValues(alpha: 0.45),
          cardColor.withValues(alpha: 0.15),
          cardColor.withValues(alpha: 0.0), // Fully transparent at bottom
        ],
        stops: const [0.0, 0.25, 0.50, 0.75, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(rrect, fillPaint);

    // 2. Border Stroke with Early Ramp:
    // Beautifully frames the top and upper sides, then fades out completely
    // past the middle so the entire lower half has zero border line.
    final strokePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          borderColor,
          borderColor.withValues(alpha: 0.70),
          borderColor.withValues(alpha: 0.20),
          borderColor.withValues(alpha: 0.0), // Fades to zero by 65% height
        ],
        stops: const [0.0, 0.20, 0.45, 0.65],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawRRect(rrect.deflate(borderWidth / 2), strokePaint);
  }

  @override
  bool shouldRepaint(covariant RampedCardPainter oldDelegate) {
    return oldDelegate.cardColor != cardColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.isInTune != isInTune ||
        oldDelegate.inTuneGlowColor != inTuneGlowColor;
  }
}

