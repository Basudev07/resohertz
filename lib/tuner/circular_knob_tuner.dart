import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:resohertz/tuner/tuning_result.dart';

/// Modern circular knob (dial) tuner visualization.
///
/// Features:
/// - Smooth 60/120fps needle interpolation without choppy double-filtering.
/// - Subtle, tasteful on/off luminescence around the knob bezel.
/// - Rich metallic French Blue dial body that remains vibrant and visible in both on and off states.
/// - Surrounding radial arc of 51 evenly spaced indicator tick bars representing pitch deviation (-50¢ to +50¢).
/// - Prominent center note display (e.g. "E2", "A2", "G#2") with octave.
/// - Tuning status direction prompt directly below note ("IN TUNE", "FLAT (Tune Up)", "SHARP (Tune Down)").
/// - Direct tap-to-toggle microphone control with responsive haptic feedback and native ripples.
class CircularKnobTuner extends StatefulWidget {
  /// Stabilized cents deviation (-50.0 to +50.0).
  final double stabilizedCents;

  /// Whether a valid pitch is detected.
  final bool isPitched;

  /// Current tuning status (inTune, flat, sharp, unpitched).
  final TuningStatus status;

  /// Active status color (lime green for in-tune, amber for flat, coral for sharp).
  final Color statusColor;

  /// Whether the app is currently in dark mode.
  final bool isDark;

  /// Formatted note name string (e.g. "E", "A", "G#", or "--").
  final String noteName;

  /// Octave number string (e.g. "2", "3", "4", or empty).
  final String noteOctave;

  /// Directional status title (e.g. "IN TUNE", "FLAT", "SHARP", "READY").
  final String statusTitle;

  /// Directional subtitle instruction (e.g. "Tune Up", "Tune Down", or null).
  final String? statusInstruction;

  /// Diameter of the entire knob tuner widget (default: 272.0).
  final double size;

  /// Callback when the knob dial is tapped to toggle mic state.
  final VoidCallback? onTap;

  /// Optional Key for the tap interaction target (e.g. start/stop capture button key).
  final Key? tapKey;

  /// Whether the tuner microphone is currently capturing.
  final bool isCapturing;

  /// Whether the app is currently displaying the Chromatic Aurora theme.
  final bool isAurora;

  const CircularKnobTuner({
    super.key,
    required this.stabilizedCents,
    required this.isPitched,
    required this.status,
    required this.statusColor,
    required this.isDark,
    required this.noteName,
    this.noteOctave = '',
    required this.statusTitle,
    this.statusInstruction,
    this.size = 272.0,
    this.onTap,
    this.tapKey,
    this.isCapturing = true,
    this.isAurora = false,
  });

  @override
  State<CircularKnobTuner> createState() => _CircularKnobTunerState();
}

class _CircularKnobTunerState extends State<CircularKnobTuner>
    with TickerProviderStateMixin {
  late AnimationController _onOffController;
  late Animation<double> _onOffAnimation;

  late AnimationController _needleController;
  late Animation<double> _needleAnimation;
  double _targetFraction = 0.0;
  double _currentRenderedFraction = 0.0;

  @override
  void initState() {
    super.initState();

    // 1. Subtle, smooth 300ms On/Off transition
    _onOffController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.isCapturing ? 1.0 : 0.0,
    );
    _onOffAnimation = CurvedAnimation(
      parent: _onOffController,
      curve: Curves.easeInOut,
    );

    // 2. Responsive, fluid needle tracking interpolator with easeOutSine curve
    _currentRenderedFraction = _calcTargetFraction(widget.stabilizedCents, widget.isPitched);
    _targetFraction = _currentRenderedFraction;
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _needleAnimation = AlwaysStoppedAnimation<double>(_currentRenderedFraction);
  }

  double _calcTargetFraction(double cents, bool isPitched) {
    if (!isPitched) return 0.0;
    return (cents.clamp(-50.0, 50.0) / 50.0);
  }

  @override
  void didUpdateWidget(covariant CircularKnobTuner oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Smoothly transition on/off state
    if (widget.isCapturing != oldWidget.isCapturing) {
      if (widget.isCapturing) {
        _onOffController.forward();
      } else {
        _onOffController.reverse();
      }
    }

    final newTarget = _calcTargetFraction(widget.stabilizedCents, widget.isPitched);
    final targetDeltaFromCurrent = (newTarget - _targetFraction).abs();

    final currentValue = _needleAnimation.value;
    final totalDistance = (newTarget - currentValue).abs();

    // 1. Natural microphone jitter & string sustain ripple suppression:
    if (_needleController.isAnimating) {
      if (targetDeltaFromCurrent < 0.015) {
        return;
      }

      // Near-center anti-fluttering ("about to be tuned" and fading):
      // When both current position and new target are within the near-center convergence zone
      // (±2.5¢ / 0.05 fraction), do NOT rapidly whip back and forth across zero on acoustic noise.
      // Require a genuine peg adjustment (> 2.0¢ / 0.04 fraction) or wait for current glide to settle.
      final isNearCenter = newTarget.abs() < 0.05 && _targetFraction.abs() < 0.05;
      if (isNearCenter) {
        final isAlternatingSign = (newTarget * _targetFraction) <= 0;
        if (isAlternatingSign || totalDistance < 0.04) {
          return;
        }
      }

      // If the animation is in its initial acceleration phase (< 40% elapsed) and delta is minor (< 1.5¢ / 0.03 fraction),
      // avoid abrupt rapid-fire restarts to preserve weighted physical momentum.
      if (_needleController.value < 0.40 && targetDeltaFromCurrent < 0.03) {
        return;
      }
    } else {
      // When needle is resting near center, ignore tiny acoustic flutter (< 1.2¢ / 0.025 fraction)
      // to keep the dial rock-solid when about to be tuned
      if (currentValue.abs() < 0.04 && newTarget.abs() < 0.04 && totalDistance < 0.025) {
        return;
      }
    }

    // If already at target and not animating, do nothing
    if (totalDistance < 0.002 && !_needleController.isAnimating) {
      return;
    }

    // Calibrated, slightly slower durations for luxurious, weighted studio dial movement:
    // - Micro-adjustments (< 2.5¢): 280ms for refined, stable feedback
    // - Moderate adjustments (2.5¢ to 10¢): 340ms for buttery-smooth tracking
    // - Large adjustments (> 10¢, initial attack, string switch, idle return): 420ms for weighted physical sweep
    final int durationMs;
    if (totalDistance < 0.05) {
      durationMs = 280;
    } else if (totalDistance < 0.20) {
      durationMs = 340;
    } else {
      durationMs = 420;
    }

    _needleController.duration = Duration(milliseconds: durationMs);
    _needleAnimation = Tween<double>(
      begin: currentValue,
      end: newTarget,
    ).animate(
      CurvedAnimation(
        parent: _needleController,
        curve: Curves.easeOutSine,
      ),
    );
    _targetFraction = newTarget;
    _currentRenderedFraction = newTarget;
    _needleController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _onOffController.dispose();
    _needleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Center(
        child: Semantics(
          button: true,
          label: widget.isCapturing ? 'Stop Listening' : 'Start Listening',
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: widget.tapKey,
                customBorder: const CircleBorder(),
                onTap: widget.onTap,
                splashColor: widget.statusColor.withValues(alpha: 0.18),
                highlightColor: widget.statusColor.withValues(alpha: 0.08),
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _onOffAnimation,
                    _needleController,
                  ]),
                  builder: (context, child) {
                    final currentFraction = _needleAnimation.value;
                    final showIndicator = widget.isPitched || (currentFraction.abs() > 0.004 && widget.isCapturing);

                    return CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: _CircularKnobPainter(
                        fraction: currentFraction,
                        showIndicator: showIndicator,
                        isPitched: widget.isPitched,
                        status: widget.status,
                        statusColor: widget.statusColor,
                        isDark: widget.isDark,
                        isCapturing: widget.isCapturing,
                        glowIntensity: _onOffAnimation.value,
                        isAurora: widget.isAurora,
                      ),
                      child: child,
                    );
                  },
                  child: _buildKnobCenter(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Center content of the circular knob dial (Note, Octave, Status).
  Widget _buildKnobCenter(BuildContext context) {
    final isInTune = widget.status == TuningStatus.inTune;
    final themeAccent = widget.isAurora
        ? const Color(0xFF37E7FF)
        : const Color(0xFFDCF4A2);

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Center Note Name + Octave
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  key: const Key('note_name_display'),
                  widget.noteName,
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: widget.isPitched
                        ? widget.statusColor
                        : (widget.isDark
                              ? themeAccent.withValues(
                                  alpha: widget.isCapturing ? 0.70 : 0.45,
                                )
                              : Colors.black45),
                    letterSpacing: 1.5,
                    height: 1.0,
                    shadows: [
                      if (isInTune)
                        Shadow(
                          color: widget.statusColor.withValues(alpha: 0.50),
                          blurRadius: 14,
                        ),
                    ],
                  ),
                ),
                if (widget.noteOctave.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    key: const Key('note_octave_display'),
                    widget.noteOctave,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: widget.isPitched
                          ? widget.statusColor.withValues(alpha: 0.85)
                          : (widget.isDark
                                ? themeAccent.withValues(
                                    alpha: widget.isCapturing ? 0.55 : 0.35,
                                  )
                                : Colors.black26),
                      height: 1.0,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // Tuning Direction State (IN TUNE, SHARP, FLAT, TUNER OFF)
            Container(
              key: const Key('tuning_status_badge'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isInTune) ...[
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: widget.statusColor,
                        ),
                        const SizedBox(width: 4),
                      ] else if (!widget.isCapturing) ...[
                        Icon(
                          Icons.mic_off_rounded,
                          size: 14,
                          color: widget.isDark
                              ? themeAccent.withValues(alpha: 0.55)
                              : Colors.black45,
                        ),
                        const SizedBox(width: 4),
                      ] else if (widget.status == TuningStatus.unpitched) ...[
                        Icon(
                          Icons.mic_rounded,
                          size: 14,
                          color: widget.statusColor,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        widget.statusTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: widget.isPitched
                              ? widget.statusColor
                              : (widget.isDark
                                    ? themeAccent.withValues(
                                        alpha: widget.isCapturing ? 0.75 : 0.50,
                                      )
                                    : Colors.black54),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  if (widget.statusInstruction != null &&
                      widget.statusInstruction!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.statusInstruction!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: widget.isDark
                            ? themeAccent.withValues(
                                alpha: widget.isCapturing ? 0.75 : 0.45,
                              )
                            : Colors.black54,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the radial tick arc, knob bezel, and illuminated pitch indicator.
///
/// Uses clean, hardware-accelerated shaders and calibrated French Blue values
/// so the knob remains clear and vibrant in both on and off states.
class _CircularKnobPainter extends CustomPainter {
  final double fraction; // -1.0 (-50¢) to +1.0 (+50¢)
  final bool showIndicator;
  final bool isPitched;
  final TuningStatus status;
  final Color statusColor;
  final bool isDark;
  final bool isCapturing;
  final double glowIntensity; // 0.0 (off) to 1.0 (on)
  final bool isAurora;

  // Arc configuration: 250 degree radial horseshoe sweep centered at 12 o'clock (-90°)
  static const double _sweepAngleRad = 250.0 * (math.pi / 180.0);
  static const double _startAngleRad = -math.pi / 2 - (_sweepAngleRad / 2);
  static const int _totalTicks = 51; // 25 flat ticks + 1 center + 25 sharp ticks

  const _CircularKnobPainter({
    required this.fraction,
    required this.showIndicator,
    required this.isPitched,
    required this.status,
    required this.statusColor,
    required this.isDark,
    required this.isCapturing,
    required this.glowIntensity,
    this.isAurora = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final knobRadius = outerRadius * 0.72; // Inner dial radius
    final isInTune = status == TuningStatus.inTune;

    // 1. Subtle, refined bezel edge glow when ON (delicate ring halo, no harsh outer bleed)
    if (glowIntensity > 0.01) {
      final glowColor = isInTune
          ? statusColor
          : (isAurora ? const Color(0xFF37E7FF) : const Color(0xFFDCF4A2));
      final glowRadius = knobRadius + 5.0;
      final glowRect = Rect.fromCircle(center: center, radius: glowRadius);
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: (isInTune ? 0.22 : 0.12) * glowIntensity),
            Colors.transparent,
          ],
          stops: const [0.82, 1.0],
        ).createShader(glowRect);
      canvas.drawCircle(center, glowRadius, glowPaint);
    }

    // 2. Draw Radial Arc of Ticks (-50¢ to +50¢)
    final tickInnerRadius = knobRadius + 5.0;
    final tickOuterRadius = outerRadius - 4.0;
    final centerTickIndex = _totalTicks ~/ 2; // Index 25 (0¢)
    final targetTickIndex = showIndicator
        ? (centerTickIndex + (fraction * centerTickIndex)).round().clamp(0, _totalTicks - 1)
        : centerTickIndex;

    // Clear, elegant calibration tick colors (clean and visible in both states)
    final inactiveTickColor = isDark
        ? (isAurora
            ? const Color(0xFF303650).withValues(alpha: 0.65)
            : const Color(0xFF0068C7).withValues(alpha: 0.50))
        : Colors.black.withValues(alpha: 0.15);

    for (int i = 0; i < _totalTicks; i++) {
      final progress = i / (_totalTicks - 1);
      final angle = _startAngleRad + progress * _sweepAngleRad;
      final isCenterTick = i == centerTickIndex;
      final isMajorTick = (i - centerTickIndex) % 5 == 0;

      // Determine active highlight:
      // When flat (fraction < 0), ticks between targetTickIndex and centerTickIndex illuminate
      // When sharp (fraction > 0), ticks between centerTickIndex and targetTickIndex illuminate
      // When inTune and indicator has arrived within the dead-center zone (±1.5¢ / 0.03 fraction),
      // ONLY the single center tick illuminates in lime green
      bool isActive = false;
      if (showIndicator && isCapturing) {
        if (isInTune && fraction.abs() < 0.03) {
          isActive = isCenterTick;
        } else if (fraction < 0) {
          isActive = (i >= targetTickIndex && i <= centerTickIndex);
        } else if (fraction > 0) {
          isActive = (i >= centerTickIndex && i <= targetTickIndex);
        }
      }

      // Tick lengths: center tick is longest, major (every 10¢) is medium, minor is compact
      final lengthMultiplier = isCenterTick ? 1.0 : (isMajorTick ? 0.75 : 0.52);
      final currentOuterRadius = tickInnerRadius + (tickOuterRadius - tickInnerRadius) * lengthMultiplier;

      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final p1 = Offset(center.dx + tickInnerRadius * cosA, center.dy + tickInnerRadius * sinA);
      final p2 = Offset(center.dx + currentOuterRadius * cosA, center.dy + currentOuterRadius * sinA);

      final Color tickColor;
      final double strokeWidth;

      if (isCenterTick) {
        tickColor = isInTune
            ? statusColor
            : (isDark
                  ? (isAurora
                      ? const Color(0xFF37E7FF)
                      : const Color(0xFFDCF4A2).withValues(alpha: 0.85))
                  : Colors.black87);
        strokeWidth = 2.4;
      } else if (isActive) {
        tickColor = statusColor;
        strokeWidth = 2.0;
      } else {
        tickColor = inactiveTickColor;
        strokeWidth = isMajorTick ? 1.4 : 1.0;
      }

      final tickPaint = Paint()
        ..color = tickColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, tickPaint);
    }

    // 3. Draw Knob Base (Elevated 3D Dial Body)
    final knobRect = Rect.fromCircle(center: center, radius: knobRadius);

    // Knob Face Gradient Fill:
    // Rich, metallic body: Obsidian dial with chromatic brighten for Aurora, or French Blue for Classic
    final knobFillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? (isAurora
                ? [
                    Color.lerp(const Color(0xFF1E2338), const Color(0xFF282F4D), glowIntensity)!,
                    Color.lerp(const Color(0xFF121524), const Color(0xFF181C30), glowIntensity)!,
                    Color.lerp(const Color(0xFF0A0C16), const Color(0xFF0F111E), glowIntensity)!,
                  ]
                : [
                    Color.lerp(const Color(0xFF005599), const Color(0xFF005DAB), glowIntensity)!,
                    Color.lerp(const Color(0xFF004382), const Color(0xFF004D96), glowIntensity)!,
                    Color.lerp(const Color(0xFF00366D), const Color(0xFF003E7E), glowIntensity)!,
                  ])
            : [
                Colors.white,
                const Color(0xFFF4F7FB),
                const Color(0xFFE2EBF5),
              ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(knobRect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, knobRadius, knobFillPaint);

    // Knob Outer Bezel Border:
    final bezelColor = isInTune
        ? statusColor
        : (isDark
              ? (isAurora
                  ? Color.lerp(
                      const Color(0xFF343A59),
                      const Color(0xFF37E7FF),
                      glowIntensity * 0.45,
                    )!
                  : Color.lerp(
                      const Color(0xFF0075D8),
                      statusColor.withValues(alpha: 0.8),
                      glowIntensity * 0.35,
                    )!)
              : const Color(0xFFCAD7E6));

    final bezelBorderPaint = Paint()
      ..color = bezelColor
      ..strokeWidth = isInTune ? 2.4 : 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, knobRadius, bezelBorderPaint);

    // Inner Concentric Accent Ring (Fine milled metallic groove)
    final innerGroovePaint = Paint()
      ..color = isDark
          ? (isAurora
              ? const Color(0xFF37E7FF).withValues(alpha: 0.22)
              : const Color(0xFF0080EA).withValues(alpha: 0.22))
          : Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, knobRadius * 0.88, innerGroovePaint);

    // 4. Center 12 o'clock Reference Pip (Dot on top knob rim)
    final pipAngle = -math.pi / 2; // Dead top 12 o'clock
    final pipCenter = Offset(
      center.dx + (knobRadius - 7.0) * math.cos(pipAngle),
      center.dy + (knobRadius - 7.0) * math.sin(pipAngle),
    );
    final pipColor = (isInTune && showIndicator && fraction.abs() < 0.03)
        ? statusColor
        : (isDark
              ? (isAurora
                  ? const Color(0xFF37E7FF).withValues(alpha: 0.70)
                  : const Color(0xFFDCF4A2).withValues(alpha: 0.55))
              : Colors.black45);
    final pipPaint = Paint()
      ..color = pipColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pipCenter, 3.2, pipPaint);

    // 5. Active Dynamic Pointer (Needle Dot on Knob Rim)
    if (showIndicator && isCapturing) {
      final currentAngle = -math.pi / 2 + (fraction * (_sweepAngleRad / 2));
      final needleCenter = Offset(
        center.dx + (knobRadius - 7.0) * math.cos(currentAngle),
        center.dy + (knobRadius - 7.0) * math.sin(currentAngle),
      );

      // When in-tune and arrived at dead-center, the pointer seamlessly merges with the glowing center pip
      final isMergedWithCenterPip = isInTune && fraction.abs() < 0.008;
      if (!isMergedWithCenterPip) {
        final double opacity = isPitched ? 1.0 : (fraction.abs() * 5.0).clamp(0.0, 1.0);
        if (opacity > 0.01) {
          // Subtle shader halo behind pointer dot
          final dotHaloRect = Rect.fromCircle(center: needleCenter, radius: 5.0);
          final pointerHaloPaint = Paint()
            ..shader = RadialGradient(
              colors: [
                statusColor.withValues(alpha: 0.45 * opacity),
                Colors.transparent,
              ],
            ).createShader(dotHaloRect);
          canvas.drawCircle(needleCenter, 5.0, pointerHaloPaint);

          final pointerPaint = Paint()
            ..color = statusColor.withValues(alpha: opacity)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(needleCenter, 3.2, pointerPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CircularKnobPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.showIndicator != showIndicator ||
        oldDelegate.isPitched != isPitched ||
        oldDelegate.status != status ||
        oldDelegate.statusColor != statusColor ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isCapturing != isCapturing ||
        oldDelegate.glowIntensity != glowIntensity ||
        oldDelegate.isAurora != isAurora;
  }
}
