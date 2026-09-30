import 'package:flutter/material.dart';
import 'package:resohertz/tuner/tuning_result.dart';

/// Custom painter rendering an authentic guitar-pick (plectrum) shape.
/// The bottom tip of the pick points downwards to mark the exact pitch on the scale.
class GuitarPickPainter extends CustomPainter {
  final Color fillColor;
  final Color borderColor;
  final bool isInTune;
  final bool isPitched;

  const GuitarPickPainter({
    required this.fillColor,
    required this.borderColor,
    this.isInTune = false,
    this.isPitched = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Path of a classic 351 teardrop guitar pick pointing DOWN
    final path = Path();
    // Top-left shoulder
    path.moveTo(w * 0.22, 0);
    // Smooth convex top edge
    path.quadraticBezierTo(w * 0.50, -h * 0.05, w * 0.78, 0);
    // Top-right shoulder
    path.quadraticBezierTo(w, h * 0.12, w * 0.90, h * 0.36);
    // Right side sweeping down to pointed bottom tip
    path.cubicTo(w * 0.82, h * 0.65, w * 0.62, h * 0.92, w * 0.50, h);
    // Left side sweeping up from bottom tip
    path.cubicTo(w * 0.38, h * 0.92, w * 0.18, h * 0.65, w * 0.10, h * 0.36);
    // Top-left shoulder
    path.quadraticBezierTo(0, h * 0.12, w * 0.22, 0);
    path.close();

    // Drop shadow or glowing halo when in tune
    if (isInTune) {
      final glowPaint = Paint()
        ..color = fillColor.withValues(alpha: 0.65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawPath(path, glowPaint);
    } else if (isPitched) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);
    }

    // Body fill with subtle vertical gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fillColor,
          fillColor.withValues(alpha: isPitched ? 0.85 : 0.4),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Border stroke
    final borderPaint = Paint()
      ..color = borderColor.withValues(alpha: isPitched ? 0.9 : 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(path, borderPaint);

    // Central grip embossing dot
    final gripPaint = Paint()
      ..color = borderColor.withValues(alpha: isPitched ? 0.5 : 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.50, h * 0.38), 2.5, gripPaint);
  }

  @override
  bool shouldRepaint(covariant GuitarPickPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.isInTune != isInTune ||
        oldDelegate.isPitched != isPitched;
  }
}

/// Horizontal tuning scale widget with guitar-pick location marker.
///
/// Features:
/// - Replaces rectangular box-style indicator with an open horizontal scale.
/// - The guitar-pick marker slides smoothly left/right according to [stabilizedCents].
/// - When in tune, the pick aligns precisely at dead-center with illuminated feedback.
class HorizontalTuningScale extends StatefulWidget {
  final double stabilizedCents;
  final bool isPitched;
  final TuningStatus status;
  final Color statusColor;
  final bool isDark;

  const HorizontalTuningScale({
    super.key,
    required this.stabilizedCents,
    required this.isPitched,
    required this.status,
    required this.statusColor,
    required this.isDark,
  });

  @override
  State<HorizontalTuningScale> createState() => _HorizontalTuningScaleState();
}

class _HorizontalTuningScaleState extends State<HorizontalTuningScale> {
  double _lastAlignment = 0.0;

  @override
  Widget build(BuildContext context) {
    final isInTune = widget.status == TuningStatus.inTune;

    if (widget.isPitched) {
      _lastAlignment = (widget.stabilizedCents / 50.0).clamp(-1.0, 1.0);
    }

    final targetAlignment = widget.isPitched ? _lastAlignment : 0.0;

    final scaleTrackColor = widget.isDark
        ? const Color(0xFF00376B)
        : Colors.black.withValues(alpha: 0.08);

    final tickColor = widget.isDark ? const Color(0xFFDCF4A2) : Colors.black87;

    const pickWidth = 22.0;
    const pickHeight = 26.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scale labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '-50¢',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.isDark
                    ? const Color(0xFFDCF4A2).withValues(alpha: 0.7)
                    : Colors.black54,
              ),
            ),
            Text(
              '0¢ (In Tune)',
              style: TextStyle(
                fontSize: 11,
                color: isInTune
                    ? widget.statusColor
                    : (widget.isDark
                          ? const Color(0xFFDCF4A2)
                          : Colors.black87),
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '+50¢',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.isDark
                    ? const Color(0xFFDCF4A2).withValues(alpha: 0.7)
                    : Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Scale Track & Animated Pick Marker
        SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Static scale background wrapped in RepaintBoundary for 60Hz/120Hz performance
              RepaintBoundary(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Horizontal Scale Track Line
                    Positioned(
                      bottom: 6,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: scaleTrackColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Ruler Tick Marks (-50¢ to +50¢, 21 marks)
                    Positioned(
                      bottom: 0,
                      left: pickWidth / 2,
                      right: pickWidth / 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(21, (index) {
                          final isMajor = index % 5 == 0;
                          final isCenter = index == 10;
                          final tickHeight = isCenter
                              ? 20.0
                              : (isMajor ? 12.0 : 7.0);
                          final tickWidth = isCenter
                              ? 2.5
                              : (isMajor ? 1.5 : 1.0);

                          return Container(
                            width: tickWidth,
                            height: tickHeight,
                            decoration: BoxDecoration(
                              color: isCenter
                                  ? (isInTune
                                        ? widget.statusColor
                                        : widget.statusColor.withValues(
                                            alpha: 0.8,
                                          ))
                                  : tickColor.withValues(
                                      alpha: isMajor ? 0.45 : 0.18,
                                    ),
                              borderRadius: BorderRadius.circular(1),
                              boxShadow: isCenter && isInTune
                                  ? [
                                      BoxShadow(
                                        color: widget.statusColor.withValues(
                                          alpha: 0.6,
                                        ),
                                        blurRadius: 4,
                                        spreadRadius: 0.5,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),

              // Smooth Physics-Eased Guitar Pick Marker (Optimized for 120Hz & 60Hz displays)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: targetAlignment),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                builder: (context, animValue, child) {
                  return Align(
                    alignment: Alignment(animValue, -0.2),
                    child: child,
                  );
                },
                child: RepaintBoundary(
                  child: SizedBox(
                    key: const Key('guitar_pick_marker'),
                    width: pickWidth,
                    height: pickHeight,
                    child: CustomPaint(
                      painter: GuitarPickPainter(
                        fillColor: widget.isPitched
                            ? widget.statusColor
                            : (widget.isDark
                                  ? const Color(
                                      0xFFDCF4A2,
                                    ).withValues(alpha: 0.3)
                                  : Colors.grey.withValues(alpha: 0.3)),
                        borderColor: widget.isDark
                            ? const Color(0xFF00376B)
                            : Colors.white,
                        isInTune: isInTune,
                        isPitched: widget.isPitched,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
