import 'dart:ui' show Offset;

import '../models/sensor_data.dart';
import 'constants.dart';

class SlashState {
  bool isSlashing = false;
  DateTime? slashStartTime;
  double peakAngularVelocity = 0.0;
  Offset? slashDirection;

  static const double _slashThreshold =
      AppConstants.slashAngularVelocityThreshold;
  static const double _forceThreshold =
      AppConstants.slashForceAngularVelocity;
  static const double _slashEndThreshold = 40.0;
  static const Duration _maxSlashDuration = Duration(milliseconds: 500);

  bool update({
    required double angularVelocity,
    required Offset currentPoint,
    required Offset? previousPoint,
    required DateTime timestamp,
  }) {
    final wasSlashing = isSlashing;

    if (angularVelocity >= _slashThreshold) {
      if (!isSlashing) {
        isSlashing = true;
        slashStartTime = timestamp;
        peakAngularVelocity = angularVelocity;
      } else {
        if (angularVelocity > peakAngularVelocity) {
          peakAngularVelocity = angularVelocity;
        }
      }

      if (previousPoint != null) {
        final dx = currentPoint.dx - previousPoint.dx;
        final dy = currentPoint.dy - previousPoint.dy;
        final len = (dx * dx + dy * dy);
        if (len > 0.00001) {
          slashDirection = Offset(dx, dy);
        }
      }
    } else if (isSlashing) {
      final slashAge = slashStartTime != null
          ? timestamp.difference(slashStartTime!)
          : Duration.zero;

      if (angularVelocity < _slashEndThreshold ||
          slashAge > _maxSlashDuration) {
        isSlashing = false;
        slashStartTime = null;
        peakAngularVelocity = 0.0;
        slashDirection = null;
      }
    }

    return isSlashing;
  }

  double get slashIntensity {
    if (!isSlashing) return 0.0;
    return ((peakAngularVelocity - _slashThreshold) /
            (_forceThreshold - _slashThreshold))
        .clamp(0.3, 1.0);
  }

  bool get isForceSlash => peakAngularVelocity >= _forceThreshold;

  void reset() {
    isSlashing = false;
    slashStartTime = null;
    peakAngularVelocity = 0.0;
    slashDirection = null;
  }
}
