import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bianzhong_app/models/vision_stick_frame.dart';
import 'package:bianzhong_app/utils/calibration_mapping.dart';

void main() {
  group('VisionStickFrame', () {
    test('parses stick_frame JSON', () {
      final frame = VisionStickFrame.fromJson({
        'type': 'stick_frame',
        'stick_id': 2,
        'x': 0.42,
        'y': 0.68,
        'confidence': 0.95,
        'visible': true,
        'timestamp': 1710000000123,
      });

      expect(frame.stickId, 2);
      expect(frame.x, closeTo(0.42, 0.001));
      expect(frame.y, closeTo(0.68, 0.001));
      expect(frame.confidence, closeTo(0.95, 0.001));
      expect(frame.isVisible, isTrue);
    });

    test('tryParse ignores non stick messages', () {
      final frame = VisionStickFrame.tryParse(
        jsonEncode({'type': 'pong', 'timestamp': 1}),
      );
      expect(frame, isNull);
    });
  });

  group('CalibrationMapping', () {
    setUp(CalibrationMapping.reset);

    test('records global and per-bell offsets', () {
      CalibrationMapping.recordSampleForBell(25, const Offset(0.02, -0.01));
      CalibrationMapping.recordSampleForBell(25, const Offset(0.04, -0.02));

      expect(CalibrationMapping.globalOffset.dx, closeTo(0.03, 0.001));
      expect(
        CalibrationMapping.perBellOffsets[25]!.dx,
        closeTo(0.03, 0.001),
      );
      expect(
        CalibrationMapping.adjustPointForBell(25, const Offset(0.5, 0.5)).dx,
        closeTo(0.44, 0.001),
      );
    });
  });
}
