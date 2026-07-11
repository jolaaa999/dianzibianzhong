import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'constants.dart';

class BladeTrailPoint {
  final Offset position;
  final DateTime timestamp;
  final bool isSlashing;

  const BladeTrailPoint({
    required this.position,
    required this.timestamp,
    required this.isSlashing,
  });
}

class BladeTrail {
  final List<BladeTrailPoint> _points = [];

  List<BladeTrailPoint> get points => List.unmodifiable(_points);

  bool get isSlashing => _points.isNotEmpty && _points.last.isSlashing;

  void addPoint(Offset position, DateTime timestamp, bool isSlashing) {
    _points.add(BladeTrailPoint(
      position: position,
      timestamp: timestamp,
      isSlashing: isSlashing,
    ));
    while (_points.length > AppConstants.bladeTrailMaxLength) {
      _points.removeAt(0);
    }
  }

  List<BladeTrailSegment> getActiveSegments() {
    if (_points.length < 2) return [];
    final now = DateTime.now();
    final cutoff = now.subtract(AppConstants.slashTrailFadeDuration);
    final segments = <BladeTrailSegment>[];
    for (int i = 1; i < _points.length; i++) {
      final prev = _points[i - 1];
      final curr = _points[i];
      if (curr.timestamp.isBefore(cutoff) && prev.timestamp.isBefore(cutoff)) {
        continue;
      }
      final dx = curr.position.dx - prev.position.dx;
      final dy = curr.position.dy - prev.position.dy;
      final length = (dx * dx + dy * dy);
      if (length < AppConstants.trailHitMinSegmentLength *
          AppConstants.trailHitMinSegmentLength) {
        continue;
      }
      final age = now.difference(curr.timestamp);
      final fadeRatio = (1.0 -
              age.inMilliseconds /
                  AppConstants.slashTrailFadeDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      segments.add(BladeTrailSegment(
        start: prev.position,
        end: curr.position,
        isSlashing: curr.isSlashing || prev.isSlashing,
        opacity: fadeRatio,
        progress: i / _points.length,
      ));
    }
    return segments;
  }

  void clear() {
    _points.clear();
  }
}

class BladeTrailSegment {
  final Offset start;
  final Offset end;
  final bool isSlashing;
  final double opacity;
  final double progress;

  const BladeTrailSegment({
    required this.start,
    required this.end,
    required this.isSlashing,
    required this.opacity,
    required this.progress,
  });

  bool intersectsRect(Rect rect) {
    if (rect.contains(start) || rect.contains(end)) {
      return true;
    }
    return _lineIntersectsRect(start, end, rect);
  }

  static bool _lineIntersectsRect(Offset p1, Offset p2, Rect rect) {
    final edges = [
      (rect.topLeft, rect.topRight),
      (rect.topRight, rect.bottomRight),
      (rect.bottomRight, rect.bottomLeft),
      (rect.bottomLeft, rect.topLeft),
    ];
    for (final (a, b) in edges) {
      if (_segmentsIntersect(p1, p2, a, b)) return true;
    }
    return false;
  }

  static bool _segmentsIntersect(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d1 = _cross(p3, p4, p1);
    final d2 = _cross(p3, p4, p2);
    final d3 = _cross(p1, p2, p3);
    final d4 = _cross(p1, p2, p4);
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    if (d1 == 0 && _onSegment(p3, p4, p1)) return true;
    if (d2 == 0 && _onSegment(p3, p4, p2)) return true;
    if (d3 == 0 && _onSegment(p1, p2, p3)) return true;
    if (d4 == 0 && _onSegment(p1, p2, p4)) return true;
    return false;
  }

  static double _cross(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }

  static bool _onSegment(Offset p, Offset q, Offset r) {
    return r.dx <= math.max(p.dx, q.dx) &&
        r.dx >= math.min(p.dx, q.dx) &&
        r.dy <= math.max(p.dy, q.dy) &&
        r.dy >= math.min(p.dy, q.dy);
  }
}
