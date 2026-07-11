import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:bianzhong_app/utils/constants.dart';
import 'package:bianzhong_app/utils/vision_strike_detector.dart';

void main() {
  group('VisionStrikeDetector', () {
    late VisionStrikeDetector detector;

    setUp(() {
      detector = VisionStrikeDetector()
        ..minStrikeSpeed = 0.5
        ..hoverSpeedThreshold = 0.2;
    });

    test('does not strike while hovering slowly', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      for (var i = 0; i < 8; i++) {
        final hits = detector.update(
          stickId: 1,
          point: Offset(0.5 + i * 0.001, 0.78),
          timestamp: t0.add(Duration(milliseconds: i * 16)),
          currentOctave: AppConstants.defaultOctave,
        );
        expect(hits, isEmpty);
      }
    });

    test('respects stick cooldown', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      Offset point = const Offset(0.5, 0.78);

      for (var i = 0; i < 6; i++) {
        point = Offset(point.dx + 0.08, point.dy);
        detector.update(
          stickId: 1,
          point: point,
          timestamp: t0.add(Duration(milliseconds: i * 16)),
          currentOctave: AppConstants.defaultOctave,
        );
      }

      final firstStrike = detector.update(
        stickId: 1,
        point: const Offset(0.5, 0.78),
        timestamp: t0.add(const Duration(milliseconds: 120)),
        currentOctave: AppConstants.defaultOctave,
      );

      final secondStrike = detector.update(
        stickId: 1,
        point: const Offset(0.5, 0.78),
        timestamp: t0.add(const Duration(milliseconds: 150)),
        currentOctave: AppConstants.defaultOctave,
      );

      expect(firstStrike.length + secondStrike.length, lessThanOrEqualTo(1));
    });
  });
}
