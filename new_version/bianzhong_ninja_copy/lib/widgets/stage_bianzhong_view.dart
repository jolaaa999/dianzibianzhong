import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/sensor_data.dart';
import '../services/udp_hammer_service.dart';
import '../utils/blade_trail.dart';
import '../utils/constants.dart';
import '../utils/stage_hit_mapper.dart';

const double _stageBellWidthRatio = 0.124;
const double _stageBellHeightRatio = 0.34;
const double _stageUpperRowTopRatio = 0.08;
const double _stageLowerRowTopRatio = 0.54;
const double _stageUpperBeamTopInsetRatio = -0.056;
const double _stageLowerBeamTopInsetRatio = -0.056;
const double _stageBeamHeightRatio = 0.064;

class _BianzhongRackPainter extends CustomPainter {
  const _BianzhongRackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shaderRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final beamShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xffc4956a), Color(0xffa67c55)],
    ).createShader(shaderRect);
    final beamPaint = Paint()..shader = beamShader;

    void drawBeam(Rect rect) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.008)),
        beamPaint,
      );
    }

    drawBeam(
      Rect.fromLTWH(
        size.width * 0.05,
        size.height * (_stageUpperRowTopRatio + _stageUpperBeamTopInsetRatio),
        size.width * 0.90,
        size.height * _stageBeamHeightRatio,
      ),
    );
    drawBeam(
      Rect.fromLTWH(
        size.width * 0.03,
        size.height * (_stageLowerRowTopRatio + _stageLowerBeamTopInsetRatio),
        size.width * 0.94,
        size.height * _stageBeamHeightRatio,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BianzhongBellPainter extends CustomPainter {
  final bool isActive;
  final Set<StageStrikeRegion>? highlightedRegions;
  final bool isFollowCurrent;
  final int notePulse;
  final bool flashActive;
  final bool drawBody;

  const _BianzhongBellPainter({
    required this.isActive,
    required this.highlightedRegions,
    this.isFollowCurrent = false,
    this.notePulse = 0,
    this.flashActive = false,
    this.drawBody = true,
  });

  Set<StageStrikeRegion> get _effectiveHighlightedRegions =>
      highlightedRegions ?? const <StageStrikeRegion>{};

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    if (!drawBody) {
      _drawStrikeRegions(
        canvas,
        Rect.fromLTWH(width * 0.10, height * 0.29, width * 0.80, height * 0.62),
      );
      return;
    }

    final bellRect = Rect.fromLTWH(
      width * 0.07,
      height * 0.20,
      width * 0.86,
      height * 0.74,
    );
    final shell = _buildShellPath(bellRect);

    canvas.drawShadow(
      shell,
      const Color(0xff241006).withValues(alpha: 0.48),
      width * 0.10,
      false,
    );

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isFollowCurrent
            ? const [
                Color(0xfffff3b0),
                Color(0xffffce62),
                Color(0xffcf7817),
                Color(0xff6f350b),
              ]
            : isActive
            ? const [
                Color(0xffffdc82),
                Color(0xffe6a13c),
                Color(0xff9a5213),
                Color(0xff4b2308),
              ]
            : const [
                Color(0xffefbd61),
                Color(0xffc47b24),
                Color(0xff81420f),
                Color(0xff3b1b07),
              ],
        stops: const [0.0, 0.28, 0.66, 1.0],
      ).createShader(bellRect);
    canvas.drawPath(shell, bodyPaint);

    canvas.save();
    canvas.clipPath(shell);
    _drawBronzeTexture(canvas, bellRect);
    canvas.drawRect(
      Rect.fromLTWH(
        bellRect.left,
        bellRect.top + bellRect.height * 0.84,
        bellRect.width,
        bellRect.height * 0.16,
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00773d0d), Color(0xaa3a1905)],
        ).createShader(bellRect),
    );
    canvas.restore();

    if (flashActive) {
      canvas.drawPath(
        shell,
        Paint()..color = const Color(0xfffff1c2).withValues(alpha: 0.48),
      );
    }

    final edgePaint = Paint()
      ..color = const Color(0xff4a2309)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.018
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(shell, edgePaint);
    canvas.drawPath(
      shell,
      Paint()
        ..color = (isFollowCurrent || isActive)
            ? const Color(0xffffe6a2)
            : const Color(0xfff3c875).withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.006
        ..strokeJoin = StrokeJoin.round,
    );

    _drawHandle(canvas, bellRect);
    _drawUpperBands(canvas, bellRect);
    _drawStudRows(canvas, bellRect);
    _drawCenterPlaque(canvas, bellRect);
    _drawLowerPatterns(canvas, bellRect);
    _drawStrikeRegions(canvas, bellRect);
  }

  Path _buildShellPath(Rect rect) {
    return Path()
      ..moveTo(rect.left + rect.width * 0.12, rect.top + rect.height * 0.06)
      ..quadraticBezierTo(
        rect.left + rect.width * 0.50,
        rect.top + rect.height * 0.015,
        rect.left + rect.width * 0.88,
        rect.top + rect.height * 0.06,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.96,
        rect.top + rect.height * 0.11,
        rect.left + rect.width * 0.96,
        rect.top + rect.height * 0.23,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.94,
        rect.top + rect.height * 0.60,
        rect.left + rect.width * 0.91,
        rect.top + rect.height * 0.94,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.88,
        rect.bottom,
        rect.left + rect.width * 0.80,
        rect.bottom,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.50,
        rect.bottom + rect.height * 0.018,
        rect.left + rect.width * 0.20,
        rect.bottom,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.12,
        rect.bottom,
        rect.left + rect.width * 0.09,
        rect.top + rect.height * 0.94,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.06,
        rect.top + rect.height * 0.60,
        rect.left + rect.width * 0.04,
        rect.top + rect.height * 0.23,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.04,
        rect.top + rect.height * 0.11,
        rect.left + rect.width * 0.12,
        rect.top + rect.height * 0.06,
      )
      ..close();
  }

  void _drawHandle(Canvas canvas, Rect rect) {
    final crownRect = Rect.fromLTWH(
      rect.left + rect.width * 0.04,
      rect.top - rect.height * 0.23,
      rect.width * 0.92,
      rect.height * 0.30,
    );
    final bronzeShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isActive || isFollowCurrent
          ? const [Color(0xffffe08b), Color(0xffd58b2c), Color(0xff6a310b)]
          : const [Color(0xffe4ad50), Color(0xffad651a), Color(0xff4d2208)],
    ).createShader(crownRect);
    final crownPaint = Paint()
      ..shader = bronzeShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.052
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final crownHighlightPaint = Paint()
      ..color = const Color(0xffffd980).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.012
      ..strokeCap = StrokeCap.round;

    void drawCreature({required bool mirror}) {
      canvas.save();
      if (mirror) {
        canvas.translate(rect.center.dx * 2, 0);
        canvas.scale(-1, 1);
      }
      final path = Path()
        ..moveTo(rect.center.dx - rect.width * 0.02, rect.top)
        ..cubicTo(
          rect.center.dx - rect.width * 0.10,
          rect.top - rect.height * 0.02,
          rect.center.dx - rect.width * 0.08,
          rect.top - rect.height * 0.17,
          rect.center.dx - rect.width * 0.20,
          rect.top - rect.height * 0.18,
        )
        ..cubicTo(
          rect.center.dx - rect.width * 0.31,
          rect.top - rect.height * 0.19,
          rect.center.dx - rect.width * 0.27,
          rect.top - rect.height * 0.05,
          rect.center.dx - rect.width * 0.36,
          rect.top - rect.height * 0.04,
        )
        ..cubicTo(
          rect.center.dx - rect.width * 0.44,
          rect.top - rect.height * 0.03,
          rect.center.dx - rect.width * 0.44,
          rect.top - rect.height * 0.13,
          rect.center.dx - rect.width * 0.38,
          rect.top - rect.height * 0.14,
        );
      canvas.drawPath(path, crownPaint);
      canvas.drawPath(
        path.shift(Offset(0, -rect.height * 0.006)),
        crownHighlightPaint,
      );
      canvas.drawCircle(
        Offset(
          rect.center.dx - rect.width * 0.115,
          rect.top - rect.height * 0.155,
        ),
        rect.width * 0.052,
        Paint()..shader = bronzeShader,
      );
      canvas.drawCircle(
        Offset(
          rect.center.dx - rect.width * 0.098,
          rect.top - rect.height * 0.17,
        ),
        rect.width * 0.010,
        Paint()..color = const Color(0xff351506),
      );
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(
            rect.center.dx - rect.width * 0.36,
            rect.top - rect.height * 0.105,
          ),
          radius: rect.width * 0.075,
        ),
        math.pi * 0.08,
        math.pi * 1.45,
        false,
        crownHighlightPaint,
      );
      canvas.restore();
    }

    drawCreature(mirror: false);
    drawCreature(mirror: true);

    final ringRect = Rect.fromCenter(
      center: Offset(rect.center.dx, rect.top - rect.height * 0.18),
      width: rect.width * 0.22,
      height: rect.height * 0.18,
    );
    canvas.drawOval(
      ringRect,
      Paint()
        ..shader = bronzeShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.042,
    );

    final strapRect = Rect.fromLTWH(
      rect.left + rect.width * 0.465,
      rect.top - rect.height * 0.25,
      rect.width * 0.07,
      rect.height * 0.30,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(strapRect, Radius.circular(rect.width * 0.018)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xff3b1907), Color(0xff9c5a1b), Color(0xff321305)],
        ).createShader(strapRect),
    );

    final crownBaseRect = Rect.fromLTWH(
      rect.left + rect.width * 0.06,
      rect.top - rect.height * 0.015,
      rect.width * 0.88,
      rect.height * 0.09,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        crownBaseRect,
        Radius.circular(rect.width * 0.025),
      ),
      Paint()..shader = bronzeShader,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        crownBaseRect,
        Radius.circular(rect.width * 0.025),
      ),
      Paint()
        ..color = const Color(0xffffd77a).withValues(alpha: 0.58)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.010,
    );
  }

  void _drawBronzeTexture(Canvas canvas, Rect rect) {
    for (int index = 0; index < 42; index++) {
      final xRatio = 0.05 + ((index * 37) % 97) / 108;
      final yRatio = 0.05 + ((index * 53 + 17) % 101) / 112;
      final center = Offset(
        rect.left + rect.width * xRatio,
        rect.top + rect.height * yRatio,
      );
      final radius = rect.width * (0.0025 + (index % 4) * 0.0014);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color =
              (index.isEven ? const Color(0xff4a2308) : const Color(0xffffd06b))
                  .withValues(alpha: index.isEven ? 0.24 : 0.18),
      );
    }
  }

  void _drawUpperBands(Canvas canvas, Rect rect) {
    final bandPaint = Paint()
      ..color = const Color(0xffffcf70).withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.015;

    final accentPaint = Paint()
      ..color = const Color(0xff542507).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.008;

    final bandRows = <double>[0.13, 0.33, 0.52, 0.70];
    for (final t in bandRows) {
      final y = rect.top + rect.height * t;
      final path = Path()
        ..moveTo(rect.left + rect.width * 0.065, y)
        ..quadraticBezierTo(
          rect.left + rect.width * 0.50,
          y - rect.height * 0.010,
          rect.left + rect.width * 0.935,
          y,
        );
      canvas.drawPath(path.shift(Offset(0, rect.height * 0.008)), accentPaint);
      canvas.drawPath(path, bandPaint);
    }

    final reliefPaint = Paint()
      ..color = const Color(0xff5f2b09).withValues(alpha: 0.58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.008
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (int index = 0; index < 10; index++) {
      final x = rect.left + rect.width * (0.09 + index * 0.084);
      final y = rect.top + rect.height * 0.085;
      final motif = Path()
        ..moveTo(x, y + rect.height * 0.022)
        ..lineTo(x + rect.width * 0.018, y)
        ..lineTo(x + rect.width * 0.040, y + rect.height * 0.020)
        ..lineTo(x + rect.width * 0.022, y + rect.height * 0.045)
        ..lineTo(x + rect.width * 0.050, y + rect.height * 0.057);
      canvas.drawPath(motif, reliefPaint);
    }
  }

  void _drawStudRows(Canvas canvas, Rect rect) {
    final rows = <double>[0.23, 0.42, 0.61];
    final columns = <double>[0.14, 0.26, 0.36];
    for (final row in rows) {
      final y = rect.top + rect.height * row;
      for (final x in columns) {
        final leftCenter = Offset(rect.left + rect.width * x, y);
        final rightCenter = Offset(rect.right - rect.width * x, y);
        _drawStud(canvas, rect, leftCenter);
        _drawStud(canvas, rect, rightCenter);
      }
    }
  }

  void _drawStud(Canvas canvas, Rect rect, Offset center) {
    final radius = rect.width * 0.036;
    canvas.drawCircle(
      center.translate(radius * 0.22, radius * 0.30),
      radius * 1.08,
      Paint()..color = const Color(0xff351506).withValues(alpha: 0.58),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [
            isActive || isFollowCurrent
                ? const Color(0xffffe59a)
                : const Color(0xffffc963),
            const Color(0xffa75e16),
            const Color(0xff4b2007),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    final spiralPaint = Paint()
      ..color = const Color(0xff5c2808).withValues(alpha: 0.84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.007
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.66),
      -math.pi * 0.35,
      math.pi * 1.62,
      false,
      spiralPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.34),
      math.pi * 0.05,
      math.pi * 1.42,
      false,
      spiralPaint,
    );
  }

  void _drawCenterPlaque(Canvas canvas, Rect rect) {
    final plaquePath = Path()
      ..moveTo(rect.left + rect.width * 0.405, rect.top + rect.height * 0.145)
      ..lineTo(rect.left + rect.width * 0.595, rect.top + rect.height * 0.145)
      ..lineTo(rect.left + rect.width * 0.575, rect.top + rect.height * 0.675)
      ..lineTo(rect.left + rect.width * 0.425, rect.top + rect.height * 0.675)
      ..close();

    final plaquePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0xffffd67a), Color(0xffd8932f), Color(0xff8f4c12)],
      ).createShader(rect);
    canvas.drawPath(plaquePath, plaquePaint);
    canvas.drawPath(
      plaquePath,
      Paint()
        ..color = const Color(0xff5a2708).withValues(alpha: 0.82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.018,
    );
    canvas.drawPath(
      plaquePath,
      Paint()
        ..color = const Color(0xffffe3a1).withValues(alpha: 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.006,
    );

    final weatheringPaint = Paint()
      ..color = const Color(0xff71370d).withValues(alpha: 0.30)
      ..strokeWidth = rect.width * 0.005
      ..strokeCap = StrokeCap.round;
    for (int index = 0; index < 7; index++) {
      final y = rect.top + rect.height * (0.20 + index * 0.062);
      final insetRatio = 0.445 + (index % 2) * 0.02;
      canvas.drawLine(
        Offset(rect.left + rect.width * insetRatio, y),
        Offset(rect.right - rect.width * insetRatio, y + rect.height * 0.012),
        weatheringPaint,
      );
    }
  }

  void _drawLowerPatterns(Canvas canvas, Rect rect) {
    final panelRect = Rect.fromLTWH(
      rect.left + rect.width * 0.10,
      rect.top + rect.height * 0.72,
      rect.width * 0.80,
      rect.height * 0.17,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, Radius.circular(rect.width * 0.018)),
      Paint()..color = const Color(0xff6b300a).withValues(alpha: 0.32),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, Radius.circular(rect.width * 0.018)),
      Paint()
        ..color = const Color(0xffffc65d).withValues(alpha: 0.48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.010,
    );

    final patternPaint = Paint()
      ..color = const Color(0xff542306).withValues(alpha: 0.70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.007
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    for (int row = 0; row < 3; row++) {
      for (int column = 0; column < 8; column++) {
        final x = panelRect.left + panelRect.width * (0.035 + column * 0.12);
        final y = panelRect.top + panelRect.height * (0.18 + row * 0.28);
        final motif = Path()
          ..moveTo(x, y)
          ..lineTo(x + panelRect.width * 0.045, y)
          ..lineTo(x + panelRect.width * 0.045, y + panelRect.height * 0.14)
          ..lineTo(x + panelRect.width * 0.075, y + panelRect.height * 0.14)
          ..lineTo(x + panelRect.width * 0.075, y + panelRect.height * 0.25);
        canvas.drawPath(motif, patternPaint);
      }
    }
  }

  void _drawStrikeRegions(Canvas canvas, Rect rect) {
    final strikeLayout = StageHitMapper.resolveStrikeLayoutForShellRect(rect);
    final highlightLeft = _effectiveHighlightedRegions.contains(
      StageStrikeRegion.left,
    );
    final highlightRight = _effectiveHighlightedRegions.contains(
      StageStrikeRegion.right,
    );
    final highlightCenter = _effectiveHighlightedRegions.contains(
      StageStrikeRegion.center,
    );

    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    _paintStrikeRegion(
      canvas: canvas,
      path: strikeLayout.leftPath,
      glowPaint: glowPaint,
      fillColor: const Color(0xff9b5918),
      edgeColor: const Color(0xffffce72),
      isHighlighted: highlightLeft,
      strokeWidth: rect.width * 0.017,
    );
    _paintStrikeRegion(
      canvas: canvas,
      path: strikeLayout.rightPath,
      glowPaint: glowPaint,
      fillColor: const Color(0xff9b5918),
      edgeColor: const Color(0xffffce72),
      isHighlighted: highlightRight,
      strokeWidth: rect.width * 0.017,
    );
    _paintStrikeRegion(
      canvas: canvas,
      path: strikeLayout.centerPath,
      glowPaint: glowPaint,
      fillColor: const Color(0xffc87924),
      edgeColor: const Color(0xffffe3a5),
      isHighlighted: highlightCenter,
      strokeWidth: rect.width * 0.017,
    );
  }

  void _paintStrikeRegion({
    required Canvas canvas,
    required Path path,
    required Paint glowPaint,
    required Color fillColor,
    required Color edgeColor,
    required bool isHighlighted,
    required double strokeWidth,
  }) {
    if (isHighlighted) {
      glowPaint.color = edgeColor.withValues(alpha: 0.58);
      canvas.drawPath(path, glowPaint);
    }

    final fillPaint = Paint()
      ..color = fillColor.withValues(alpha: isHighlighted ? 0.34 : 0.045)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final edgePaint = Paint()
      ..color = edgeColor.withValues(alpha: isHighlighted ? 0.96 : 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHighlighted ? strokeWidth * 1.45 : strokeWidth;
    canvas.drawPath(path, edgePaint);

    if (!isHighlighted) {
      return;
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xfffff0c7).withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.52,
    );
  }

  @override
  bool shouldRepaint(covariant _BianzhongBellPainter oldDelegate) {
    final previousRegions = oldDelegate._effectiveHighlightedRegions;
    final currentRegions = _effectiveHighlightedRegions;
    return oldDelegate.isActive != isActive ||
        oldDelegate.isFollowCurrent != isFollowCurrent ||
        oldDelegate.notePulse != notePulse ||
        oldDelegate.flashActive != flashActive ||
        oldDelegate.drawBody != drawBody ||
        previousRegions.length != currentRegions.length ||
        previousRegions.any((region) => !currentRegions.contains(region));
  }
}

class _HammerPainter extends CustomPainter {
  final Color accent;
  final bool isStrike;
  static const double headCenterDxRatio = 0.50;
  static const double headCenterDyRatio = 0.14;

  const _HammerPainter({required this.accent, required this.isStrike});

  @override
  void paint(Canvas canvas, Size size) {
    final shaftWidth = size.width * 0.16;
    final shaftRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.42,
        size.height * 0.18,
        shaftWidth,
        size.height * 0.60,
      ),
      Radius.circular(size.width * 0.05),
    );
    final shaftPaint = Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xffead6ad), Color(0xffb98f61), Color(0xff6d4a2b)],
          ).createShader(
            Rect.fromLTWH(
              size.width * 0.40,
              size.height * 0.16,
              size.width * 0.20,
              size.height * 0.66,
            ),
          );
    canvas.drawRRect(shaftRect, shaftPaint);

    final headRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.16,
        size.height * 0.04,
        size.width * 0.68,
        size.height * 0.20,
      ),
      Radius.circular(size.height * 0.08),
    );
    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          accent.withValues(alpha: isStrike ? 0.98 : 0.88),
          Color.lerp(accent, Colors.white, 0.25)!,
          accent.withValues(alpha: isStrike ? 0.98 : 0.88),
        ],
      ).createShader(headRect.outerRect);
    canvas.drawRRect(headRect, headPaint);

    final rimPaint = Paint()
      ..color = const Color(0xff20150d).withValues(alpha: 0.66)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.028;
    canvas.drawRRect(headRect, rimPaint);
    canvas.drawRRect(shaftRect, rimPaint);

    final capPaint = Paint()
      ..color = Colors.white.withValues(alpha: isStrike ? 0.95 : 0.70);
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.88),
      size.width * 0.065,
      capPaint,
    );

    final headCenter = Offset(
      size.width * headCenterDxRatio,
      size.height * headCenterDyRatio,
    );
    canvas.drawCircle(
      headCenter,
      size.width * 0.055,
      Paint()..color = Colors.white.withValues(alpha: isStrike ? 0.92 : 0.72),
    );
    canvas.drawCircle(
      headCenter,
      size.width * 0.028,
      Paint()..color = const Color(0xff25170d).withValues(alpha: 0.60),
    );
  }

  @override
  bool shouldRepaint(covariant _HammerPainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.isStrike != isStrike;
  }
}

class StageBellConfig {
  final String note;
  final double x;
  final bool isUpper;
  final double visualScale;

  const StageBellConfig({
    required this.note,
    required this.x,
    required this.isUpper,
    required this.visualScale,
  });
}

class StageBianzhongView extends StatefulWidget {
  final int currentOctave;
  final int? lastStrikeBellId;
  final Set<int> activeBellIds;
  final List<ActiveHammerInfo> activeHammers;
  final List<SensorData> hammerSensorStates;
  final bool ninjaMode;
  final Map<String, BladeTrail> bladeTrails;
  final int? followAlongCurrentBellId;
  final int followAlongNotePulse;
  final void Function(int bellId, double intensity, {StageStrikeRegion region})
  onBellTapped;

  const StageBianzhongView({
    super.key,
    required this.currentOctave,
    required this.lastStrikeBellId,
    required this.activeBellIds,
    required this.activeHammers,
    required this.hammerSensorStates,
    this.ninjaMode = false,
    this.bladeTrails = const {},
    this.followAlongCurrentBellId,
    this.followAlongNotePulse = 0,
    required this.onBellTapped,
  });

  static const List<StageBellConfig> _bells = [
    StageBellConfig(note: 'C', x: 0.08, isUpper: false, visualScale: 1.12),
    StageBellConfig(note: 'D', x: 0.22, isUpper: false, visualScale: 1.10),
    StageBellConfig(note: 'E', x: 0.36, isUpper: false, visualScale: 1.08),
    StageBellConfig(note: 'F', x: 0.50, isUpper: false, visualScale: 1.05),
    StageBellConfig(note: 'G', x: 0.64, isUpper: false, visualScale: 1.03),
    StageBellConfig(note: 'A', x: 0.78, isUpper: false, visualScale: 1.01),
    StageBellConfig(note: 'B', x: 0.92, isUpper: false, visualScale: 0.98),
    StageBellConfig(note: 'C#', x: 0.20, isUpper: true, visualScale: 1.12),
    StageBellConfig(note: 'D#', x: 0.35, isUpper: true, visualScale: 1.10),
    StageBellConfig(note: 'F#', x: 0.50, isUpper: true, visualScale: 1.08),
    StageBellConfig(note: 'G#', x: 0.65, isUpper: true, visualScale: 1.06),
    StageBellConfig(note: 'A#', x: 0.80, isUpper: true, visualScale: 1.04),
  ];

  @override
  State<StageBianzhongView> createState() => _StageBianzhongViewState();
}

class _StageBianzhongViewState extends State<StageBianzhongView>
    with SingleTickerProviderStateMixin {
  final Map<int, StageStrikeHitResult> _activePointerHits = {};
  static const double _stageBellPaintHeightFactor = 0.92;
  static const double _stageBellShellLeftInset = 0.08;
  static const double _stageBellShellTopInset = 0.11;
  static const double _stageBellShellWidthFactor = 0.84;
  static const double _stageBellShellHeightFactor = 0.84;

  Offset _cursorPos = Offset.zero;
  bool _cursorVisible = false;
  double _hammerStrikeY = 0.0;
  late final AnimationController _strikeController;
  final BladeTrail _mouseTrail = BladeTrail();
  bool _mouseDown = false;
  Offset? _lastTrailPos;
  final Map<String, DateTime> _mouseTrailHitTimes = {};
  final Set<int> _flashBellIds = {};
  int _lastNotePulse = 0;

  @override
  void initState() {
    super.initState();
    _strikeController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(() {
          final t = _strikeController.value;
          setState(() {
            _hammerStrikeY = t < 0.3
                ? -8.0 * (t / 0.3)
                : -8.0 * (1.0 - (t - 0.3) / 0.7);
          });
        });
  }

  @override
  void didUpdateWidget(StageBianzhongView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.followAlongNotePulse != oldWidget.followAlongNotePulse &&
        widget.followAlongCurrentBellId != null) {
      final bellId = widget.followAlongCurrentBellId!;
      _flashBellIds.add(bellId);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() => _flashBellIds.remove(bellId));
        }
      });
    }
  }

  @override
  void dispose() {
    _strikeController.dispose();
    super.dispose();
  }

  void _triggerStrike() {
    _strikeController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final sensorByDeviceId = <String, SensorData>{
      for (final sensor in widget.hammerSensorStates)
        if (sensor.deviceId != null) sensor.deviceId!: sensor,
    };
    final highlightedRegionsByBellId = <int, Set<StageStrikeRegion>>{};
    for (final sensor in widget.hammerSensorStates) {
      final stageX = sensor.stageX;
      final stageY = sensor.stageY;
      if (stageX == null || stageY == null) {
        continue;
      }
      final hit = StageHitMapper.hitTestStagePoint(
        currentOctave: widget.currentOctave,
        point: Offset(stageX, stageY),
      );
      if (hit == null) {
        continue;
      }
      highlightedRegionsByBellId
          .putIfAbsent(hit.bellId, () => <StageStrikeRegion>{})
          .add(hit.region);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final frameRect = Rect.fromLTWH(
          size.width * 0.05,
          size.height * 0.06,
          size.width * 0.90,
          size.height * 0.84,
        );

        final allTrails = <String, BladeTrail>{
          if (widget.ninjaMode) ...widget.bladeTrails,
          if (widget.ninjaMode) '_mouse': _mouseTrail,
        };

        return MouseRegion(
          onHover: (event) => setState(() {
            _cursorPos = event.localPosition;
            _cursorVisible = true;
          }),
          onEnter: (_) => setState(() => _cursorVisible = true),
          onExit: (_) => setState(() => _cursorVisible = false),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              _handlePointerDown(size, event);
              _triggerStrike();
              _mouseDown = true;
              final pos = Offset(
                event.localPosition.dx / size.width,
                event.localPosition.dy / size.height,
              );
              _lastTrailPos = pos;
              _mouseTrail.addPoint(pos, DateTime.now(), true);
            },
            onPointerMove: (event) {
              _handlePointerMove(size, event);
              setState(() => _cursorPos = event.localPosition);
              if (_mouseDown && _lastTrailPos != null) {
                final pos = Offset(
                  event.localPosition.dx / size.width,
                  event.localPosition.dy / size.height,
                );
                final dx = pos.dx - _lastTrailPos!.dx;
                final dy = pos.dy - _lastTrailPos!.dy;
                if (dx * dx + dy * dy > 0.0004) {
                  _mouseTrail.addPoint(pos, DateTime.now(), true);
                  _lastTrailPos = pos;
                  if (widget.ninjaMode && _mouseTrail.points.length > 1) {
                    _processMouseTrailHits();
                  }
                }
              }
            },
            onPointerUp: (event) {
              _activePointerHits.remove(event.pointer);
              _mouseDown = false;
              _lastTrailPos = null;
              _mouseTrailHitTimes.clear();
            },
            onPointerCancel: (event) {
              _activePointerHits.remove(event.pointer);
              _mouseDown = false;
              _lastTrailPos = null;
              _mouseTrailHitTimes.clear();
            },
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xfff2ecd9)),
              child: Stack(
                children: [
                  // 钟体 + 横梁（静态层）
                  RepaintBoundary(
                    child: Stack(
                      children: [
                        for (final bell in StageBianzhongView._bells)
                          _buildBell(
                            size: size,
                            bell: bell,
                            highlightedRegionsByBellId: highlightedRegionsByBellId,
                          ),
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _BianzhongRackPainter()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 光标 + 残影（动态层，每帧刷新）
                  for (final hammer in widget.activeHammers)
                    _buildHammer(
                      size: size,
                      frameRect: frameRect,
                      hammer: hammer,
                      sensor: sensorByDeviceId[hammer.deviceId],
                    ),
                  if (widget.ninjaMode)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _BladeTrailPainter(
                            trails: allTrails,
                            size: size,
                          ),
                        ),
                      ),
                    ),
                  if (_cursorVisible)
                    Positioned(
                      left: _cursorPos.dx - 12,
                      top: _cursorPos.dy - 6,
                      child: IgnorePointer(
                        child: Transform.translate(
                          offset: Offset(0, _hammerStrikeY),
                          child: const CustomPaint(
                            size: Size(24, 30),
                            painter: _VirtualHammerPainter(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBell({
    required Size size,
    required StageBellConfig bell,
    required Map<int, Set<StageStrikeRegion>> highlightedRegionsByBellId,
  }) {
    final bellId = BellMapping.getBellId(widget.currentOctave, bell.note);
    if (bellId == null) {
      return const SizedBox.shrink();
    }

    final upperScale = bell.isUpper ? 0.94 : 1.10;
    final scale = upperScale * bell.visualScale;
    final width = size.width * _stageBellWidthRatio * scale;
    final height = size.height * _stageBellHeightRatio * scale;
    final centerX = bell.x * size.width;
    final top =
        size.height *
        (bell.isUpper ? _stageUpperRowTopRatio : _stageLowerRowTopRatio);
    final isActive =
        widget.activeBellIds.contains(bellId) ||
        bellId == widget.lastStrikeBellId;
    final isFollowCurrent = widget.followAlongCurrentBellId == bellId;
    final highlightedRegions =
        highlightedRegionsByBellId[bellId] ?? const <StageStrikeRegion>{};

    return Positioned(
      left: centerX - width / 2,
      top: top,
      width: width,
      height: height * 1.08,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width,
              height: height * 0.92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/bell_reference.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    color: _flashBellIds.contains(bellId)
                        ? const Color(0x66ffffff)
                        : isFollowCurrent
                        ? const Color(0x36ffe08a)
                        : isActive
                        ? const Color(0x24ffc765)
                        : null,
                    colorBlendMode: BlendMode.screen,
                    errorBuilder: (context, error, stackTrace) => CustomPaint(
                      painter: _BianzhongBellPainter(
                        isActive: isActive,
                        highlightedRegions: highlightedRegions,
                        isFollowCurrent: isFollowCurrent,
                        notePulse: isFollowCurrent
                            ? widget.followAlongNotePulse
                            : 0,
                        flashActive: _flashBellIds.contains(bellId),
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _BianzhongBellPainter(
                      isActive: isActive,
                      highlightedRegions: highlightedRegions,
                      isFollowCurrent: isFollowCurrent,
                      notePulse: isFollowCurrent
                          ? widget.followAlongNotePulse
                          : 0,
                      flashActive: _flashBellIds.contains(bellId),
                      drawBody: false,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _numberedNotationLabel(bell.note),
              style: TextStyle(
                color: const Color(0xff3d2b1f).withValues(alpha: 0.90),
                fontSize: math.max(11, size.width * 0.016),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _numberedNotationLabel(String note) {
    return switch (note) {
      'C' => '1',
      'C#' => '♯1',
      'D' => '2',
      'D#' => '♯2',
      'E' => '3',
      'F' => '4',
      'F#' => '♯4',
      'G' => '5',
      'G#' => '♯5',
      'A' => '6',
      'A#' => '♯6',
      'B' => '7',
      _ => note,
    };
  }

  Widget _buildHammer({
    required Size size,
    required Rect frameRect,
    required ActiveHammerInfo hammer,
    required SensorData? sensor,
  }) {
    if (sensor == null) {
      return Positioned(
        left: frameRect.left + 18 + (hammer.seatIndex * 40.0) - 14,
        top: frameRect.top + 14,
        width: 28,
        height: 40,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.35,
            child: CustomPaint(
              painter: const _HammerPainter(
                accent: Color(0xffd6d6d6),
                isStrike: false,
              ),
            ),
          ),
        ),
      );
    }

    final roll = _normalizeSignedDegrees(sensor.roll ?? 0.0);
    final normalizedX = sensor.stageX?.clamp(0.0, 1.0) ?? 0.5;
    final normalizedY = sensor.stageY?.clamp(0.0, 1.0) ?? 0.5;
    final centerX = size.width * normalizedX;
    final centerY = size.height * normalizedY;
    const hammerWidth = 48.0;
    const hammerHeight = 62.0;
    final headCenterOffset = Offset(
      hammerWidth * _HammerPainter.headCenterDxRatio,
      hammerHeight * _HammerPainter.headCenterDyRatio,
    );
    final accent = hammer.hand == HammerHand.left
        ? const Color(0xff4fc3ff)
        : const Color(0xffffc14f);

    return Positioned(
      left: centerX - headCenterOffset.dx,
      top: centerY - headCenterOffset.dy,
      width: hammerWidth,
      height: hammerHeight,
      child: IgnorePointer(
        child: Center(
          child: Transform.rotate(
            angle: roll * math.pi / 180.0,
            child: Transform.translate(
              offset: Offset(0, sensor.strike ? -4 : 0),
              child: CustomPaint(
                size: const Size(hammerWidth, hammerHeight),
                painter: _HammerPainter(
                  accent: accent,
                  isStrike: sensor.strike,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handlePointerDown(Size size, PointerDownEvent event) {
    final hit = _hitTestPointer(size, event.localPosition);
    if (hit == null) {
      return;
    }
    _activePointerHits[event.pointer] = hit;
    _triggerHit(hit);
  }

  void _handlePointerMove(Size size, PointerMoveEvent event) {
    if (event.buttons == 0 && event.kind != PointerDeviceKind.touch) {
      return;
    }
    final previous = _activePointerHits[event.pointer];
    final current = _hitTestPointer(size, event.localPosition);
    if (current == null) {
      _activePointerHits.remove(event.pointer);
      return;
    }
    if (previous != null &&
        previous.bellId == current.bellId &&
        previous.region == current.region) {
      return;
    }
    _activePointerHits[event.pointer] = current;
    _triggerHit(current);
  }

  StageStrikeHitResult? _hitTestPointer(Size size, Offset localPosition) {
    StageStrikeHitResult? bestMatch;
    double bestDistance = double.infinity;

    for (final bell in StageBianzhongView._bells) {
      final bellId = BellMapping.getBellId(widget.currentOctave, bell.note);
      if (bellId == null) {
        continue;
      }

      final upperScale = bell.isUpper ? 0.94 : 1.10;
      final scale = upperScale * bell.visualScale;
      final width = size.width * _stageBellWidthRatio * scale;
      final height = size.height * _stageBellHeightRatio * scale;
      final bellTop =
          size.height *
          (bell.isUpper ? _stageUpperRowTopRatio : _stageLowerRowTopRatio);
      final bellLeft = bell.x * size.width - width / 2;
      final paintHeight = height * _stageBellPaintHeightFactor;
      final shellRect = Rect.fromLTWH(
        bellLeft + width * _stageBellShellLeftInset,
        bellTop + paintHeight * _stageBellShellTopInset,
        width * _stageBellShellWidthFactor,
        paintHeight * _stageBellShellHeightFactor,
      );
      final strikeLayout = StageHitMapper.resolveStrikeLayoutForShellRect(
        shellRect,
      );

      void consider({
        required Path path,
        required Rect rect,
        required StageStrikeRegion region,
      }) {
        if (!path.contains(localPosition)) {
          return;
        }
        final distance = (localPosition - rect.center).distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestMatch = StageStrikeHitResult(bellId: bellId, region: region);
        }
      }

      consider(
        path: strikeLayout.leftPath,
        rect: strikeLayout.leftRect,
        region: StageStrikeRegion.left,
      );
      consider(
        path: strikeLayout.rightPath,
        rect: strikeLayout.rightRect,
        region: StageStrikeRegion.right,
      );
      consider(
        path: strikeLayout.centerPath,
        rect: strikeLayout.centerRect,
        region: StageStrikeRegion.center,
      );
    }

    return bestMatch;
  }

  void _triggerHit(StageStrikeHitResult hit) {
    widget.onBellTapped(hit.bellId, 0.85, region: hit.region);
  }

  void _processMouseTrailHits() {
    final segments = _mouseTrail.getActiveSegments();
    final trailHits = StageHitMapper.hitTestTrailSegments(
      currentOctave: widget.currentOctave,
      segments: segments
          .map((s) => (start: s.start, end: s.end, isSlashing: s.isSlashing))
          .toList(),
    );
    final now = DateTime.now();
    for (final hit in trailHits) {
      final key = '${hit.bellId}:${hit.region.index}';
      final lastTime = _mouseTrailHitTimes[key];
      if (lastTime != null &&
          now.difference(lastTime) < const Duration(milliseconds: 300)) {
        continue;
      }
      _mouseTrailHitTimes[key] = now;
      _triggerStrike();
      widget.onBellTapped(hit.bellId, 0.85, region: hit.region);
    }
  }

  double _normalizeSignedDegrees(double degrees) {
    var value = degrees % 360.0;
    if (value > 180.0) value -= 360.0;
    if (value < -180.0) value += 360.0;
    return value;
  }
}

class _VirtualHammerPainter extends CustomPainter {
  const _VirtualHammerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shaftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xffc4956a), Color(0xff8b6b4a)],
      ).createShader(const Rect.fromLTWH(9, 12, 6, 18));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.70),
          width: 5,
          height: size.height * 0.50,
        ),
        const Radius.circular(2.5),
      ),
      shaftPaint,
    );

    final headPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff5a8fc9), Color(0xff2a5a8a)],
      ).createShader(const Rect.fromLTWH(4, 2, 16, 10));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.18),
          width: size.width * 0.70,
          height: size.height * 0.30,
        ),
        const Radius.circular(4),
      ),
      headPaint,
    );

    final rimPaint = Paint()
      ..color = const Color(0xff1a2a3a).withValues(alpha: 0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.18),
          width: size.width * 0.70,
          height: size.height * 0.30,
        ),
        const Radius.circular(4),
      ),
      rimPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BladeTrailPainter extends CustomPainter {
  final Map<String, BladeTrail> trails;
  final Size size;

  const _BladeTrailPainter({required this.trails, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    for (final trail in trails.values) {
      final segments = trail.getActiveSegments();
      if (segments.isEmpty) continue;

      for (final seg in segments) {
        final start = Offset(
          seg.start.dx * canvasSize.width,
          seg.start.dy * canvasSize.height,
        );
        final end = Offset(
          seg.end.dx * canvasSize.width,
          seg.end.dy * canvasSize.height,
        );

        if (seg.isSlashing) {
          final glowPaint = Paint()
            ..color = Color.fromRGBO(100, 200, 255, seg.opacity * 0.4)
            ..strokeWidth = AppConstants.bladeTrailGlowWidth
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
          canvas.drawLine(start, end, glowPaint);

          final bladePaint = Paint()
            ..color = Color.fromRGBO(200, 240, 255, seg.opacity * 0.9)
            ..strokeWidth = AppConstants.bladeTrailWidth
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawLine(start, end, bladePaint);
        } else {
          final dimPaint = Paint()
            ..color = Color.fromRGBO(150, 180, 200, seg.opacity * 0.25)
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(start, end, dimPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BladeTrailPainter oldDelegate) => true;
}
