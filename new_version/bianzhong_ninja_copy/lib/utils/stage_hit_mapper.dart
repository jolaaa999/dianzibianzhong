import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'constants.dart';
import '../models/sensor_data.dart';

enum StageStrikeRegion { left, right, center }

const double _stageBellWidthRatio = 0.124;
const double _stageBellHeightRatio = 0.34;
const double _stageBellPaintHeightFactor = 0.92;
const double _stageBellShellLeftInset = 0.08;
const double _stageBellShellTopInset = 0.11;
const double _stageBellShellWidthFactor = 0.84;
const double _stageBellShellHeightFactor = 0.84;

class StageStrikeHitResult {
  final int bellId;
  final StageStrikeRegion region;

  const StageStrikeHitResult({
    required this.bellId,
    required this.region,
  });
}

class TrailHitResult {
  final int bellId;
  final StageStrikeRegion region;

  const TrailHitResult({
    required this.bellId,
    required this.region,
  });
}

class StageBellLayoutConfig {
  final String note;
  final double x;
  final double y;
  final bool isUpper;
  final double visualScale;

  const StageBellLayoutConfig({
    required this.note,
    required this.x,
    required this.y,
    required this.isUpper,
    required this.visualScale,
  });
}

class _StageBellGeometry {
  final Rect shellRect;

  const _StageBellGeometry({required this.shellRect});
}

class StageStrikeLayout {
  final Rect leftRect;
  final Rect rightRect;
  final Rect centerRect;
  final Rect leftHitRect;
  final Rect rightHitRect;
  final Rect centerHitRect;
  final Path leftPath;
  final Path rightPath;
  final Path centerPath;

  const StageStrikeLayout({
    required this.leftRect,
    required this.rightRect,
    required this.centerRect,
    required this.leftHitRect,
    required this.rightHitRect,
    required this.centerHitRect,
    required this.leftPath,
    required this.rightPath,
    required this.centerPath,
  });
}

class StageHitMapper {
  static const double _yawMaxDegrees = 60.0;
  static const double _pitchMaxDegrees = 60.0;
  static const double _yawGain = 1.0;
  static const double _pitchGain = 1.0;

  static const List<StageBellLayoutConfig> bellLayouts = [
    StageBellLayoutConfig(note: 'C', x: 0.10, y: 0.78, isUpper: false, visualScale: 1.10),
    StageBellLayoutConfig(note: 'D', x: 0.23, y: 0.78, isUpper: false, visualScale: 1.06),
    StageBellLayoutConfig(note: 'E', x: 0.36, y: 0.78, isUpper: false, visualScale: 1.02),
    StageBellLayoutConfig(note: 'F', x: 0.50, y: 0.78, isUpper: false, visualScale: 1.00),
    StageBellLayoutConfig(note: 'G', x: 0.64, y: 0.78, isUpper: false, visualScale: 0.97),
    StageBellLayoutConfig(note: 'A', x: 0.77, y: 0.78, isUpper: false, visualScale: 0.94),
    StageBellLayoutConfig(note: 'B', x: 0.90, y: 0.78, isUpper: false, visualScale: 0.92),
    StageBellLayoutConfig(note: 'C#', x: 0.25, y: 0.27, isUpper: true, visualScale: 1.12),
    StageBellLayoutConfig(note: 'D#', x: 0.375, y: 0.27, isUpper: true, visualScale: 1.04),
    StageBellLayoutConfig(note: 'F#', x: 0.50, y: 0.27, isUpper: true, visualScale: 0.96),
    StageBellLayoutConfig(note: 'G#', x: 0.625, y: 0.27, isUpper: true, visualScale: 0.88),
    StageBellLayoutConfig(note: 'A#', x: 0.75, y: 0.27, isUpper: true, visualScale: 0.80),
  ];

  static Offset sensorToStagePoint({
    required double yaw,
    required double pitch,
  }) {
    return projectRelativeDisplayPoint(yaw: yaw, pitch: pitch);
  }

  static Offset projectRelativeDisplayPoint({
    required double yaw,
    required double pitch,
  }) {
    final normalizedYaw = _normalizeSignedDegrees(yaw);
    final normalizedPitch = _normalizeSignedDegrees(pitch);
    return _eulerToStagePoint(
      yawDeg: normalizedYaw,
      pitchDeg: normalizedPitch,
      leftInset: 0.02,
      rightInset: 0.02,
      topInset: 0.03,
      bottomInset: 0.03,
    );
  }

  static Offset projectRelativeDirectionDisplayPoint({
    required Vector3 direction,
  }) {
    final angles = _directionToEuler(direction);
    return _eulerToStagePoint(
      yawDeg: angles.yaw,
      pitchDeg: angles.pitch,
      leftInset: 0.02,
      rightInset: 0.02,
      topInset: 0.03,
      bottomInset: 0.03,
    );
  }

  static Offset? sensorToStrikeStagePoint({
    required double yaw,
    required double pitch,
    required double roll,
  }) {
    return projectRelativeStrikePoint(yaw: yaw, pitch: pitch, roll: roll);
  }

  static Offset? projectRelativeStrikePoint({
    required double yaw,
    required double pitch,
    required double roll,
  }) {
    final normalizedYaw = _normalizeSignedDegrees(yaw);
    final normalizedPitch = _normalizeSignedDegrees(pitch);
    final _ = _normalizeSignedDegrees(roll);
    return _eulerToStagePoint(
      yawDeg: normalizedYaw,
      pitchDeg: normalizedPitch,
      leftInset: 0.05,
      rightInset: 0.05,
      topInset: 0.06,
      bottomInset: 0.10,
    );
  }

  static Offset projectRelativeDirectionStrikePoint({
    required Vector3 direction,
  }) {
    final angles = _directionToEuler(direction);
    return _eulerToStagePoint(
      yawDeg: angles.yaw,
      pitchDeg: angles.pitch,
      leftInset: 0.05,
      rightInset: 0.05,
      topInset: 0.06,
      bottomInset: 0.10,
    );
  }

  static ({double yaw, double pitch}) _directionToEuler(Vector3 direction) {
    final yawDeg = math.atan2(direction.x, direction.z) * 57.2957795;
    final pitchDeg = math.asin((-direction.y).clamp(-1.0, 1.0)) * 57.2957795;
    return (yaw: yawDeg, pitch: pitchDeg);
  }

  static Offset _eulerToStagePoint({
    required double yawDeg,
    required double pitchDeg,
    required double leftInset,
    required double rightInset,
    required double topInset,
    required double bottomInset,
  }) {
    final normalizedX = (0.5 - (yawDeg / _yawMaxDegrees) * 0.5 * _yawGain)
        .clamp(0.0, 1.0);
    final normalizedY = (0.5 + (pitchDeg / _pitchMaxDegrees) * 0.5 * _pitchGain)
        .clamp(0.0, 1.0);
    return Offset(
      leftInset + (1.0 - leftInset - rightInset) * normalizedX,
      topInset + (1.0 - topInset - bottomInset) * normalizedY,
    );
  }

  static StageStrikeHitResult? hitTestStagePoint({
    required int currentOctave,
    required Offset point,
  }) {
    StageStrikeHitResult? bestMatch;
    double bestDistance = double.infinity;

    for (final bell in bellLayouts) {
      final bellId = BellMapping.getBellId(currentOctave, bell.note);
      if (bellId == null) {
        continue;
      }

      final geometry = _resolveBellGeometry(bell);
      final shellRect = geometry.shellRect;
      final strikeLayout = resolveStrikeLayoutForShellRect(shellRect);

      void consider({
        required Path path,
        required Rect rect,
        required StageStrikeRegion region,
      }) {
        if (!path.contains(point)) {
          return;
        }
        final distance = (point - rect.center).distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestMatch = StageStrikeHitResult(
            bellId: bellId,
            region: region,
          );
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

  static List<TrailHitResult> hitTestTrailSegments({
    required int currentOctave,
    required List<({Offset start, Offset end, bool isSlashing})> segments,
  }) {
    final hits = <TrailHitResult>[];
    final hitBellIds = <int>{};

    for (final seg in segments) {
      if (!seg.isSlashing) continue;

      for (final bell in bellLayouts) {
        final bellId = BellMapping.getBellId(currentOctave, bell.note);
        if (bellId == null || hitBellIds.contains(bellId)) continue;

        final geometry = _resolveBellGeometry(bell);
        final shellRect = geometry.shellRect;
        final strikeLayout = resolveStrikeLayoutForShellRect(shellRect);

        StageStrikeRegion? hitRegion;
        double bestDist = double.infinity;

        void checkRegion(Path path, Rect rect, StageStrikeRegion region) {
          if (_segmentIntersectsPath(seg.start, seg.end, path, rect)) {
            final dist = _pointToSegmentDistance(rect.center, seg.start, seg.end);
            if (dist < bestDist) {
              bestDist = dist;
              hitRegion = region;
            }
          }
        }

        checkRegion(strikeLayout.leftPath, strikeLayout.leftRect, StageStrikeRegion.left);
        checkRegion(strikeLayout.rightPath, strikeLayout.rightRect, StageStrikeRegion.right);
        checkRegion(strikeLayout.centerPath, strikeLayout.centerRect, StageStrikeRegion.center);

        if (hitRegion != null) {
          hitBellIds.add(bellId);
          hits.add(TrailHitResult(bellId: bellId, region: hitRegion!));
        }
      }
    }

    return hits;
  }

  static bool _segmentIntersectsPath(Offset p1, Offset p2, Path path, Rect bounds) {
    if (bounds.contains(p1) || bounds.contains(p2)) {
      if (path.contains(p1) || path.contains(p2)) return true;
    }

    final steps = 8;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final px = p1.dx + (p2.dx - p1.dx) * t;
      final py = p1.dy + (p2.dy - p1.dy) * t;
      final point = Offset(px, py);
      if (path.contains(point)) return true;
    }

    final edges = [
      (bounds.topLeft, bounds.topRight),
      (bounds.topRight, bounds.bottomRight),
      (bounds.bottomRight, bounds.bottomLeft),
      (bounds.bottomLeft, bounds.topLeft),
    ];
    for (final (a, b) in edges) {
      if (_segmentsCross(p1, p2, a, b)) return true;
    }
    return false;
  }

  static bool _segmentsCross(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d1 = _cross(p3, p4, p1);
    final d2 = _cross(p3, p4, p2);
    final d3 = _cross(p1, p2, p3);
    final d4 = _cross(p1, p2, p4);
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    return false;
  }

  static double _cross(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }

  static double _pointToSegmentDistance(Offset point, Offset segStart, Offset segEnd) {
    final dx = segEnd.dx - segStart.dx;
    final dy = segEnd.dy - segStart.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 0.000001) return (point - segStart).distance;
    final t = ((point.dx - segStart.dx) * dx + (point.dy - segStart.dy) * dy) / lenSq;
    final clamped = t.clamp(0.0, 1.0);
    final proj = Offset(segStart.dx + clamped * dx, segStart.dy + clamped * dy);
    return (point - proj).distance;
  }

  static _StageBellGeometry _resolveBellGeometry(StageBellLayoutConfig bell) {
    final scale = (bell.isUpper ? 0.95 : 1.00) * bell.visualScale;
    final width = _stageBellWidthRatio * scale;
    final height = _stageBellHeightRatio * scale;
    final bellTop = bell.y - height / 2;
    final bellLeft = bell.x - width / 2;
    final paintHeight = height * _stageBellPaintHeightFactor;
    final shellRect = Rect.fromLTWH(
      bellLeft + width * _stageBellShellLeftInset,
      bellTop + paintHeight * _stageBellShellTopInset,
      width * _stageBellShellWidthFactor,
      paintHeight * _stageBellShellHeightFactor,
    );
    return _StageBellGeometry(shellRect: shellRect);
  }

  static StageStrikeLayout resolveStrikeLayoutForShellRect(Rect shellRect) {
    final sideTop = shellRect.top + shellRect.height * 0.56;
    final sideBottom = shellRect.top + shellRect.height * 0.80;
    final sideWidth = shellRect.width * 0.26;
    final leftPath = _buildLeftSideStrikePath(
      shellRect: shellRect,
      top: sideTop,
      bottom: sideBottom,
      width: sideWidth,
    );
    final rightPath = _buildRightSideStrikePath(
      shellRect: shellRect,
      top: sideTop,
      bottom: sideBottom,
      width: sideWidth,
    );
    final leftRect = leftPath.getBounds();
    final rightRect = rightPath.getBounds();
    final centerRect = Rect.fromLTRB(
      shellRect.left + shellRect.width * 0.25,
      shellRect.top + shellRect.height * 0.70,
      shellRect.right - shellRect.width * 0.25,
      shellRect.bottom,
    );
    final centerPath = Path()
      ..moveTo(shellRect.left + shellRect.width * 0.25, shellRect.top + shellRect.height * 0.98)
      ..quadraticBezierTo(
        shellRect.left + shellRect.width * 0.35,
        shellRect.top + shellRect.height * 0.78,
        shellRect.left + shellRect.width * 0.50,
        shellRect.top + shellRect.height * 0.70,
      )
      ..quadraticBezierTo(
        shellRect.left + shellRect.width * 0.65,
        shellRect.top + shellRect.height * 0.78,
        shellRect.left + shellRect.width * 0.75,
        shellRect.top + shellRect.height * 0.98,
      )
      ..close();
    final hitTop = shellRect.top + shellRect.height * 0.54;
    final hitBottom = shellRect.top + shellRect.height * 0.985;
    final leftHitRect = Rect.fromLTRB(
      shellRect.left + shellRect.width * 0.03,
      hitTop,
      shellRect.left + shellRect.width * 0.27,
      shellRect.top + shellRect.height * 0.90,
    );
    final rightHitRect = Rect.fromLTRB(
      shellRect.right - shellRect.width * 0.27,
      hitTop,
      shellRect.right - shellRect.width * 0.03,
      shellRect.top + shellRect.height * 0.90,
    );
    final centerHitRect = Rect.fromLTRB(
      shellRect.left + shellRect.width * 0.22,
      shellRect.top + shellRect.height * 0.68,
      shellRect.right - shellRect.width * 0.22,
      hitBottom,
    );

    return StageStrikeLayout(
      leftRect: leftRect,
      rightRect: rightRect,
      centerRect: centerRect,
      leftHitRect: leftHitRect,
      rightHitRect: rightHitRect,
      centerHitRect: centerHitRect,
      leftPath: leftPath,
      rightPath: rightPath,
      centerPath: centerPath,
    );
  }

  static Path _buildLeftSideStrikePath({
    required Rect shellRect,
    required double top,
    required double bottom,
    required double width,
  }) {
    final midY = (top + bottom) / 2;
    final outerTopX = _leftShellEdgeX(shellRect, top);
    final outerMidX = _leftShellEdgeX(shellRect, midY);
    final outerBottomX = _leftShellEdgeX(shellRect, bottom);
    final innerTopX = outerTopX + width * 0.92;
    final innerMidX = outerMidX + width * 1.02;
    final innerBottomX = outerBottomX + width * 0.86;

    return Path()
      ..moveTo(outerTopX, top)
      ..quadraticBezierTo(outerMidX, midY, outerBottomX, bottom)
      ..lineTo(innerBottomX, bottom)
      ..quadraticBezierTo(innerMidX, midY, innerTopX, top)
      ..close();
  }

  static Path _buildRightSideStrikePath({
    required Rect shellRect,
    required double top,
    required double bottom,
    required double width,
  }) {
    final midY = (top + bottom) / 2;
    final outerTopX = _rightShellEdgeX(shellRect, top);
    final outerMidX = _rightShellEdgeX(shellRect, midY);
    final outerBottomX = _rightShellEdgeX(shellRect, bottom);
    final innerTopX = outerTopX - width * 0.92;
    final innerMidX = outerMidX - width * 1.02;
    final innerBottomX = outerBottomX - width * 0.86;

    return Path()
      ..moveTo(outerTopX, top)
      ..quadraticBezierTo(outerMidX, midY, outerBottomX, bottom)
      ..lineTo(innerBottomX, bottom)
      ..quadraticBezierTo(innerMidX, midY, innerTopX, top)
      ..close();
  }

  static double _leftShellEdgeX(Rect rect, double y) {
    final t = ((y - rect.top) / rect.height).clamp(0.0, 1.0);
    if (t <= 0.17) {
      final local = t / 0.17;
      return _lerp(
        rect.left + rect.width * 0.18,
        rect.left + rect.width * 0.16,
        local,
      );
    }
    if (t <= 0.60) {
      final local = (t - 0.17) / (0.60 - 0.17);
      return _lerp(
        rect.left + rect.width * 0.16,
        rect.left + rect.width * 0.12,
        local,
      );
    }
    final local = ((t - 0.60) / (0.97 - 0.60)).clamp(0.0, 1.0);
    return _lerp(
      rect.left + rect.width * 0.12,
      rect.left + rect.width * 0.04,
      local,
    );
  }

  static double _rightShellEdgeX(Rect rect, double y) {
    final t = ((y - rect.top) / rect.height).clamp(0.0, 1.0);
    if (t <= 0.17) {
      final local = t / 0.17;
      return _lerp(
        rect.left + rect.width * 0.82,
        rect.left + rect.width * 0.84,
        local,
      );
    }
    if (t <= 0.60) {
      final local = (t - 0.17) / (0.60 - 0.17);
      return _lerp(
        rect.left + rect.width * 0.84,
        rect.left + rect.width * 0.88,
        local,
      );
    }
    final local = ((t - 0.60) / (0.97 - 0.60)).clamp(0.0, 1.0);
    return _lerp(
      rect.left + rect.width * 0.88,
      rect.left + rect.width * 0.96,
      local,
    );
  }

  static double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  static double _normalizeSignedDegrees(double degrees) {
    var value = degrees % 360.0;
    if (value > 180.0) value -= 360.0;
    if (value < -180.0) value += 360.0;
    return value;
  }
}
