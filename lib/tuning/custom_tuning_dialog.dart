import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:resohertz/tuning/guitar_string.dart';
import 'package:resohertz/tuning/reference_frequency.dart';
import 'package:resohertz/tuning/tuning_preset.dart';

/// Modal dialog for creating or editing a custom guitar tuning preset.
///
/// Allows configuring tuning name, starting from built-in templates,
/// and fine-tuning individual string pitches with semitone steppers and Hz preview.
class CustomTuningDialog extends StatefulWidget {
  final TuningPreset? presetToEdit;
  final TuningPreset? initialTemplate;
  final double referenceA4;
  final ValueChanged<TuningPreset> onSave;

  const CustomTuningDialog({
    super.key,
    this.presetToEdit,
    this.initialTemplate,
    this.referenceA4 = ReferenceFrequency.standard,
    required this.onSave,
  });

  @override
  State<CustomTuningDialog> createState() => _CustomTuningDialogState();
}

class _CustomTuningDialogState extends State<CustomTuningDialog> {
  late final TextEditingController _nameController;
  late List<GuitarString> _strings;
  String? _errorMessage;

  bool get _isEditing => widget.presetToEdit != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController = TextEditingController(text: widget.presetToEdit!.name);
      _strings = List<GuitarString>.from(widget.presetToEdit!.strings);
    } else {
      final template = widget.initialTemplate ?? TuningPreset.standard;
      _nameController = TextEditingController(text: 'Custom Tuning');
      _strings = List<GuitarString>.from(template.strings);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _applyTemplate(TuningPreset template) {
    setState(() {
      _strings = List<GuitarString>.from(template.strings);
    });
  }

  void _changePitch(int index, int semitoneDelta) {
    final current = _strings[index];
    // Clamp MIDI pitch between C1 (24 = 32.7 Hz) and C6 (84 = 1046.5 Hz)
    final newMidi = (current.midiNote + semitoneDelta).clamp(24, 84);
    if (newMidi == current.midiNote) return;

    setState(() {
      _strings[index] = current.withMidiNote(newMidi);
    });
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'Tuning name cannot be empty';
      });
      return;
    }

    final TuningPreset result;
    if (_isEditing) {
      result = widget.presetToEdit!.copyWith(
        name: name,
        strings: _strings,
        isCustom: true,
      );
    } else {
      final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      result = TuningPreset(
        id: id,
        name: name,
        strings: _strings,
        isCustom: true,
      );
    }

    widget.onSave(result);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Custom Tuning' : 'New Custom Tuning'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: math.min(420, MediaQuery.of(context).size.width * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tuning Name Input
              TextField(
                key: const Key('custom_tuning_name_field'),
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Tuning Name',
                  hintText: 'e.g. Drop B, Open C, Dadgad Flat',
                  errorText: _errorMessage,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: !_isEditing,
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() {
                      _errorMessage = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              // Template Selector Row (shown when creating)
              if (!_isEditing) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Template:',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    DropdownButton<String>(
                      isDense: true,
                      value: null,
                      hint: const Text(
                        'Load Preset...',
                        style: TextStyle(fontSize: 12),
                      ),
                      items: TuningPreset.builtInPresets.map((preset) {
                        return DropdownMenuItem<String>(
                          value: preset.id,
                          child: Text(
                            preset.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (id) {
                        if (id != null) {
                          _applyTemplate(TuningPreset.byId(id));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const Divider(),
              // String Pitch Steppers
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  'Strings Pitch (String 6 to String 1):',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
              ),
              ...List.generate(_strings.length, (index) {
                final string = _strings[index];
                final targetHz = string.frequencyAt(widget.referenceA4);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            'Str ${string.stringNumber}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        // Decrement semitone [-]
                        IconButton(
                          key: Key('decrement_string_${string.stringNumber}'),
                          icon: const Icon(Icons.remove, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () => _changePitch(index, -1),
                        ),
                        // Note + Octave + Frequency Display
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  string.displayName,
                                  key: Key(
                                    'string_display_${string.stringNumber}',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                                Text(
                                  '${targetHz.toStringAsFixed(1)} Hz',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Increment semitone [+]
                        IconButton(
                          key: Key('increment_string_${string.stringNumber}'),
                          icon: const Icon(Icons.add, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () => _changePitch(index, 1),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('custom_tuning_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('custom_tuning_save_button'),
          onPressed: _save,
          child: Text(_isEditing ? 'Save Changes' : 'Create Tuning'),
        ),
      ],
    );
  }
}
