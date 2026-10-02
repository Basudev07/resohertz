import 'package:flutter/material.dart';
import 'package:resohertz/settings/app_settings.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

/// Sleek, compact rectangular modal dialog for Reso Hertz settings.
///
/// Features only:
/// 1. Auto-Start Listening toggle
/// 2. Prefer # Note Notation toggle
class SettingsDialog extends StatefulWidget {
  final AppSettings currentSettings;
  final List<TuningPreset>? allPresets;
  final ValueChanged<AppSettings> onSave;

  const SettingsDialog({
    super.key,
    required this.currentSettings,
    this.allPresets,
    required this.onSave,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late bool _autoStart;
  late bool _preferSharps;
  late String _backgroundStyle;

  @override
  void initState() {
    super.initState();
    _autoStart = widget.currentSettings.autoStartListening;
    // preferFlats == false means preferSharps == true
    _preferSharps = !widget.currentSettings.preferFlats;
    _backgroundStyle = widget.currentSettings.backgroundStyle;
  }

  void _resetDefaults() {
    setState(() {
      _autoStart = AppSettings.defaultSettings.autoStartListening;
      _preferSharps = !AppSettings.defaultSettings.preferFlats;
      _backgroundStyle = AppSettings.defaultSettings.backgroundStyle;
    });
  }

  void _save() {
    final updated = widget.currentSettings.copyWith(
      autoStartListening: _autoStart,
      preferFlats: !_preferSharps,
      backgroundStyle: _backgroundStyle,
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFFDCF4A2);
    const cardBg = Color(0xFF004382);
    const border = Color(0xFF0068C7);

    return AlertDialog(
      backgroundColor: cardBg,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 20.0,
        vertical: 24.0,
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      contentPadding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10), // Sleek rectangular geometry
        side: const BorderSide(color: border, width: 1.2),
      ),
      title: Row(
        children: const [
          Icon(Icons.tune, color: primary, size: 20),
          SizedBox(width: 8),
          Text(
            'Settings',
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Auto-Start Listening Toggle
            SwitchListTile(
              key: const Key('auto_start_switch'),
              dense: true,
              visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
              activeThumbColor: primary,
              activeTrackColor: const Color(0xFF0055A4),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Auto-Start Listening',
                style: TextStyle(
                  color: primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Start microphone when opening app',
                style: TextStyle(
                  fontSize: 11,
                  color: primary.withValues(alpha: 0.7),
                ),
              ),
              value: _autoStart,
              onChanged: (val) => setState(() => _autoStart = val),
            ),
            const Divider(color: border, height: 10, thickness: 0.8),

            // 2. Prefer # Note Notation Toggle
            SwitchListTile(
              key: const Key('prefer_sharps_switch'),
              dense: true,
              visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
              activeThumbColor: primary,
              activeTrackColor: const Color(0xFF0055A4),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Prefer # Note Notation',
                style: TextStyle(
                  color: primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Show accidental notes with # instead of ♭',
                style: TextStyle(
                  fontSize: 11,
                  color: primary.withValues(alpha: 0.7),
                ),
              ),
              value: _preferSharps,
              onChanged: (val) => setState(() => _preferSharps = val),
            ),
            const Divider(color: border, height: 10, thickness: 0.8),

            // 3. Background Ambiance Visual Style
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 2.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Background Style',
                    style: TextStyle(
                      color: primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Choose visual ambiance (Default: French Blue)',
                    style: TextStyle(
                      fontSize: 11,
                      color: primary.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildThemeOption(
                          key: const Key('bg_style_classic'),
                          title: 'French Blue',
                          badge: 'DEFAULT',
                          selected: _backgroundStyle == 'classic',
                          accentColor: primary,
                          borderColor: border,
                          onTap: () =>
                              setState(() => _backgroundStyle = 'classic'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildThemeOption(
                          key: const Key('bg_style_aurora'),
                          title: 'Chromatic',
                          badge: 'AURORA',
                          selected: _backgroundStyle == 'aurora',
                          accentColor: const Color(0xFF37E7FF),
                          borderColor: border,
                          onTap: () =>
                              setState(() => _backgroundStyle = 'aurora'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '©BAZUD3V',
              style: TextStyle(
                color: primary.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: const Key('reset_defaults_button'),
                  onPressed: _resetDefaults,
                  child: Text(
                    'Reset',
                    style: TextStyle(
                      color: primary.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('settings_save_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: const Color(0xFF003366),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    minimumSize: const Size(72, 34),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        6,
                      ), // Sleek rectangular button
                    ),
                  ),
                  onPressed: _save,
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required Key key,
    required String title,
    required String badge,
    required bool selected,
    required Color accentColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accentColor : borderColor.withValues(alpha: 0.6),
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                Text(
                  badge,
                  style: TextStyle(
                    color: selected ? accentColor : Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: accentColor, size: 16)
            else
              const Icon(
                Icons.circle_outlined,
                color: Colors.white24,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}
