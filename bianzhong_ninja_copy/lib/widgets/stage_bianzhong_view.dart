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
const double _stageUpperBeamTopInsetRatio = -0.070;
const double _stageLowerBeamTopInsetRatio = -0.086;
const double _stageBeamHeightRatio = 0.064;

class _BianzhongRackPainter extends CustomPainter {
  const _BianzhongRackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shaderRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final beamShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xffc4956a),
        Color(0xffa67c55),
      ],
    ).createShader(shaderRect);
    final beamPaint = Paint()..shader = beamShader;

    void drawBeam(Rect rect) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(size.width * 0.008),
        ),
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

  const _BianzhongBellPainter({
    required this.isActive,
    required this.highlightedRegions,
    this.isFollowCurrent = false,
    this.notePulse = 0,
    this.flashActive = false,
  });

  Set<StageStrikeRegion> get _effectiveHighlightedRegions =>
      highlightedRegions ?? const <StageStrikeRegion>{};

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final bellRect = Rect.fromLTWH(
      width * 0.08,
      height * 0.11,
      width * 0.84,
      height * 0.84,
    );
    final shell = _buildShellPath(bellRect);
    final cavity = _buildCavityPath(bellRect);
    final body = Path.combine(PathOperation.difference, shell, cavity);

    canvas.drawShadow(
      shell,
      Colors.black.withValues(alpha: 0.34),
      width * 0.12,
      false,
    );

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isFollowCurrent
            ? const [
                Color(0xfffff176),
                Color(0xffffc107),
                Color(0xffff8f00),
              ]
            : isActive
            ? const [
                Color(0xfff0cb85),
                Color(0xffcb8f46),
                Color(0xff7f4b24),
              ]
            : const [
                Color(0xffb08658),
                Color(0xff7b5330),
                Color(0xff35221b),
              ],
      ).createShader(bellRect);
    canvas.drawPath(body, bodyPaint);

    if (flashActive) {
      canvas.drawPath(
        body,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }

    final edgePaint = Paint()
      ..color = isFollowCurrent
          ? const Color(0xffffee58)
          : isActive
          ? const Color(0xffffebbf)
          : const Color(0xffd0b08a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.020;
    canvas.drawPath(shell, edgePaint);

    _drawHandle(canvas, bellRect);
    _drawUpperBands(canvas, bellRect);
    _drawStudRows(canvas, bellRect);
    _drawCenterPlaque(canvas, bellRect);
    _drawLowerPatterns(canvas, bellRect);
    _drawStrikeRegions(canvas, bellRect);
  }

  Path _buildShellPath(Rect rect) {
    return Path()
      ..moveTo(rect.left + rect.width * 0.18, rect.top + rect.height * 0.05)
      ..quadraticBezierTo(
        rect.left + rect.width * 0.50,
        rect.top,
        rect.left + rect.width * 0.82,
        rect.top + rect.height * 0.05,
      )
      ..lineTo(rect.left + rect.width * 0.84, rect.top + rect.height * 0.17)
      ..quadraticBezierTo(
        rect.left + rect.width * 0.83,
        rect.top + rect.height * 0.36,
        rect.left + rect.width * 0.88,
        rect.top + rect.height * 0.60,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.91,
        rect.top + rect.height * 0.77,
        rect.left + rect.width * 0.96,
        rect.top + rect.height * 0.97,
      )
      ..lineTo(rect.left + rect.width * 0.74, rect.top + rect.height * 0.985)
      ..quadraticBezierTo(
        rect.left + rect.width * 0.50,
        rect.top + rect.height * 0.91,
        rect.left + rect.width * 0.26,
        rect.top + rect.height * 0.985,
      )
      ..lineTo(rect.left + rect.width * 0.04, rect.top + rect.height * 0.97)
      ..quadraticBezierTo(
        rect.left + rect.width * 0.09,
        rect.top + rect.height * 0.77,
        rect.left + rect.width * 0.12,
        rect.top + rect.height * 0.60,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.17,
        rect.top + rect.height * 0.36,
        rect.left + rect.width * 0.16,
        rect.top + rect.height * 0.17,
      )
      ..close();
  }

  Path _buildCavityPath(Rect rect) {
    return Path()
      ..moveTo(rect.left + rect.width * 0.25, rect.top + rect.height * 0.98)
      ..quadraticBezierTo(
        rect.left + rect.width * 0.35,
        rect.top + rect.height * 0.78,
        rect.left + rect.width * 0.50,
        rect.top + rect.height * 0.70,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * 0.65,
        rect.top + rect.height * 0.78,
        rect.left + rect.width * 0.75,
        rect.top + rect.height * 0.98,
      )
      ..close();
  }

  void _drawHandle(Canvas canvas, Rect rect) {
    final handlePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xff685045),
          Color(0xff3f312c),
        ],
      ).createShader(
        Rect.fromLTWH(
          rect.left + rect.width * 0.38,
          rect.top - rect.height * 0.12,
          rect.width * 0.24,
          rect.height * 0.18,
        ),
      );

    final strapRect = Rect.fromLTWH(
      rect.left + rect.width * 0.435,
      rect.top - rect.height * 0.28,
      rect.width * 0.13,
      rect.height * 0.34,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(strapRect, Radius.circular(rect.width * 0.03)),
      handlePaint,
    );

    final beamRect = Rect.fromLTWH(
      rect.left + rect.width * 0.26,
      rect.top - rect.height * 0.045,
      rect.width * 0.48,
      rect.height * 0.11,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(beamRect, Radius.circular(rect.width * 0.05)),
      handlePaint,
    );

    final ringRect = Rect.fromLTWH(
      rect.left + rect.width * 0.45,
      rect.top + rect.height * 0.01,
      rect.width * 0.10,
      rect.height * 0.12,
    );
    final ringPaint = Paint()
      ..color = const Color(0xff43342f)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.028;
    canvas.drawArc(ringRect, 0, math.pi, false, ringPaint);
  }

  void _drawUpperBands(Canvas canvas, Rect rect) {
    final bandPaint = Paint()
      ..color = const Color(0xffcab197).withValues(alpha: 0.68)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.012;

    final accentPaint = Paint()
      ..color = const Color(0xff2a1a14).withValues(alpha: 0.48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.006;

    final bandRows = <double>[0.20, 0.31, 0.43, 0.55];
    for (final t in bandRows) {
      final y = rect.top + rect.height * t;
      final path = Path()
        ..moveTo(rect.left + rect.width * 0.10, y)
        ..quadraticBezierTo(
          rect.left + rect.width * 0.50,
          y - rect.height * 0.025,
          rect.left + rect.width * 0.90,
          y,
        );
      canvas.drawPath(path, bandPaint);
      canvas.drawPath(path.shift(Offset(0, rect.height * 0.012)), accentPaint);
    }
  }

  void _drawStudRows(Canvas canvas, Rect rect) {
    final studPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          isActive ? const Color(0xffffe2a5) : const Color(0xffd9c4af),
          const Color(0xff5d4638),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(rect.center.dx, rect.center.dy),
          radius: rect.width * 0.05,
        ),
      );
    final armPaint = Paint()
      ..color = const Color(0xff5e483a)
      ..strokeWidth = rect.width * 0.015
      ..strokeCap = StrokeCap.round;

    final rows = <double>[0.22, 0.33, 0.45, 0.57];
    final columns = <double>[0.16, 0.28, 0.40];
    for (final row in rows) {
      final y = rect.top + rect.height * row;
      for (final x in columns) {
        final leftCenter = Offset(rect.left + rect.width * x, y);
        final rightCenter = Offset(rect.right - rect.width * x, y);
        canvas.drawLine(
          leftCenter.translate(-rect.width * 0.06, 0),
          leftCenter,
          armPaint,
        );
        canvas.drawLine(
          rightCenter,
          rightCenter.translate(rect.width * 0.06, 0),
          armPaint,
        );
        canvas.drawCircle(leftCenter, rect.width * 0.036, studPaint);
        canvas.drawCircle(rightCenter, rect.width * 0.036, studPaint);
      }
    }
  }

  void _drawCenterPlaque(Canvas canvas, Rect rect) {
    final plaquePath = Path()
      ..moveTo(rect.left + rect.width * 0.42, rect.top + rect.height * 0.12)
      ..lineTo(rect.left + rect.width * 0.58, rect.top + rect.height * 0.12)
      ..lineTo(rect.left + rect.width * 0.55, rect.top + rect.height * 0.60)
      ..lineTo(rect.left + rect.width * 0.45, rect.top + rect.height * 0.60)
      ..close();

    final plaquePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xff8f6a45),
          const Color(0xff523726),
        ],
      ).createShader(rect);
    canvas.drawPath(plaquePath, plaquePaint);
    canvas.drawPath(
      plaquePath,
      Paint()
        ..color = const Color(0xffd8c0a4).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.010,
    );

    final glyphPaint = Paint()
      ..color = const Color(0xff1a120d).withValues(alpha: 0.70)
      ..strokeWidth = rect.width * 0.005
      ..strokeCap = StrokeCap.round;
    for (int index = 0; index < 6; index++) {
      final y = rect.top + rect.height * (0.18 + index * 0.065);
      canvas.drawLine(
        Offset(rect.left + rect.width * 0.48, y),
        Offset(rect.left + rect.width * 0.52, y + rect.height * 0.03),
        glyphPaint,
      );
      canvas.drawLine(
        Offset(rect.left + rect.width * 0.52, y),
        Offset(rect.left + rect.width * 0.48, y + rect.height * 0.03),
        glyphPaint,
      );
    }
  }

  void _drawLowerPatterns(Canvas canvas, Rect rect) {
    final patternPaint = Paint()
      ..color = const Color(0xffc9ad87).withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.014;

    final centerX = rect.center.dx;
    final topY = rect.top + rect.height * 0.64;
    final bottomY = rect.top + rect.height * 0.83;

    canvas.drawLine(
      Offset(centerX, topY),
      Offset(centerX, bottomY),
      patternPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(centerX, topY + rect.height * 0.05),
        width: rect.width * 0.26,
        height: rect.height * 0.12,
      ),
      math.pi * 0.12,
      math.pi * 0.76,
      false,
      patternPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(centerX, topY + rect.height * 0.05),
        width: rect.width * 0.26,
        height: rect.height * 0.12,
      ),
      math.pi * 1.12,
      math.pi * 0.76,
      false,
      patternPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(centerX, bottomY - rect.height * 0.03),
        width: rect.width * 0.42,
        height: rect.height * 0.16,
      ),
      math.pi * 1.10,
      math.pi * 0.80,
      false,
      patternPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(centerX, bottomY - rect.height * 0.03),
        width: rect.width * 0.42,
        height: rect.height * 0.16,
      ),
      math.pi * 0.10,
      math.pi * 0.80,
      false,
      patternPaint,
    );
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
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    _paintStrikeRegion(
      canvas: canvas,
      path: strikeLayout.leftPath,
      glowPaint: glowPaint,
      fillColor: const Color(0xff59cbff),
      edgeColor: const Color(0xffd9f7ff),
      isHighlighted: highlightLeft,
      strokeWidth: rect.width * 0.017,
    );
    _paintStrikeRegion(
      canvas: canvas,
      path: strikeLayout.rightPath,
      glowPaint: glowPaint,
      fillColor: const Color(0xff59cbff),
      edgeColor: const Color(0xffd9f7ff),
      isHighlighted: highlightRight,
      strokeWidth: rect.width * 0.017,
    );
    _paintStrikeRegion(
      canvas: canvas,
      path: strikeLayout.centerPath,
      glowPaint: glowPaint,
      fillColor: const Color(0xffff9732),
      edgeColor: const Color(0xffffe2b0),
      isHighlighted: highlightCenter,
      strokeWidth: rect.width * 0.017,
    );

    _paintStrikeLabel(
      canvas: canvas,
      label: '侧',
      center: Offset(
        strikeLayout.leftRect.center.dx + rect.width * 0.01,
        strikeLayout.leftRect.center.dy,
      ),
      fontSize: rect.width * 0.13,
    );
    _paintStrikeLabel(
      canvas: canvas,
      label: '侧',
      center: Offset(
        strikeLayout.rightRect.center.dx - rect.width * 0.01,
        strikeLayout.rightRect.center.dy,
      ),
      fontSize: rect.width * 0.13,
    );
    _paintStrikeLabel(
      canvas: canvas,
      label: '正',
      center: Offset(
        strikeLayout.centerRect.center.dx,
        strikeLayout.centerRect.center.dy + rect.height * 0.035,
      ),
      fontSize: rect.width * 0.14,
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
    glowPaint.color = fillColor.withValues(alpha: isHighlighted ? 0.78 : 0.42);
    canvas.drawPath(path, glowPaint);

    final fillPaint = Paint()
      ..color = fillColor.withValues(alpha: isHighlighted ? 0.84 : 0.56)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final edgePaint = Paint()
      ..color = edgeColor.withValues(alpha: isHighlighted ? 1.0 : 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHighlighted ? strokeWidth * 1.45 : strokeWidth;
    canvas.drawPath(path, edgePaint);

    if (!isHighlighted) {
      return;
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.52,
    );
  }

  void _paintStrikeLabel({
    required Canvas canvas,
    required String label,
    required Offset center,
    required double fontSize,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.96),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
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
        previousRegions.length != currentRegions.length ||
        previousRegions.any(
          (region) => !currentRegions.contains(region),
        );
  }
}

class _HammerPainter extends CustomPainter {
  final Color accent;
  final bool isStrike;
  static const double headCenterDxRatio = 0.50;
  static const double headCenterDyRatio = 0.14;

  const _HammerPainter({
    required this.accent,
    required this.isStrike,
  });

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
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xffead6ad),
          Color(0xffb98f61),
          Color(0xff6d4a2b),
        ],
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
      Paint()
        ..color = Colors.white.withValues(alpha: isStrike ? 0.92 : 0.72),
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
  final void Function(
    int bellId,
    double intensity, {
    StageStrikeRegion region,
  })
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
    _strikeController = AnimationController(
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
              _mouseTrail.addPoint(
                pos, DateTime.now(), true,
              );
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
                  _mouseTrail.addPoint(
                    pos, DateTime.now(), true,
                  );
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
              decoration: const BoxDecoration(
                color: Color(0xfff2ecd9),
              ),
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
    final top = size.height *
        (bell.isUpper ? _stageUpperRowTopRatio : _stageLowerRowTopRatio);
    final isActive =
        widget.activeBellIds.contains(bellId) || bellId == widget.lastStrikeBellId;
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
              child: CustomPaint(
                painter: _BianzhongBellPainter(
                  isActive: isActive,
                  highlightedRegions: highlightedRegions,
                  isFollowCurrent: isFollowCurrent,
                  notePulse: isFollowCurrent ? widget.followAlongNotePulse : 0,
                  flashActive: _flashBellIds.contains(bellId),
                ),
                size: Size(width, height * 0.92),
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
      final bellTop = size.height *
          (bell.isUpper ? _stageUpperRowTopRatio : _stageLowerRowTopRatio);
      final bellLeft = bell.x * size.width - width / 2;
      final paintHeight = height * _stageBellPaintHeightFactor;
      final shellRect = Rect.fromLTWH(
        bellLeft + width * _stageBellShellLeftInset,
        bellTop + paintHeight * _stageBellShellTopInset,
        width * _stageBellShellWidthFactor,
        paintHeight * _stageBellShellHeightFactor,
      );
      final strikeLayout = StageHitMapper.resolveStrikeLayoutForShellRect(shellRect);

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
      if (lastTime != null && now.difference(lastTime) < const Duration(milliseconds: 300)) {
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
        final start = Offset(seg.start.dx * canvasSize.width, seg.start.dy * canvasSize.height);
        final end = Offset(seg.end.dx * canvasSize.width, seg.end.dy * canvasSize.height);

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
