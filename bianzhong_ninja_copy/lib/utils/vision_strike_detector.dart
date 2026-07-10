import 'dart:ui' show Offset;

import '../utils/constants.dart';
import '../utils/stage_hit_mapper.dart';
import '../models/vision_stick_history.dart';

enum StickMotionState { idle, hovering, striking }

class VisionStrikeHitResult {
  final int bellId;
  final StageStrikeRegion region;
  final double intensity;
  final int stickId;

  const VisionStrikeHitResult({
    required this.bellId,
    required this.region,
    required this.intensity,
    required this.stickId,
  });
}

/// 视觉版敲击检测：根据坐标历史判定悬停 vs 敲击
class VisionStrikeDetector {
  final Map<int, VisionStickHistory> _histories = {};
  final Map<int, DateTime> _stickCooldown = {};
  final Map<int, DateTime> _bellCooldown = {};
  final List<VisionStrikeHitResult> _currentBatch = [];
  DateTime? _batchStart;

  double minStrikeSpeed = AppConstants.visionMinStrikeSpeed;
  double hoverSpeedThreshold = AppConstants.visionHoverSpeedThreshold;

  void reset() {
    _histories.clear();
    _stickCooldown.clear();
    _bellCooldown.clear();
    _currentBatch.clear();
    _batchStart = null;
  }

  List<VisionStrikeHitResult> update({
    required int stickId,
    required Offset point,
    required DateTime timestamp,
    required int currentOctave,
  }) {
    final history = _histories.putIfAbsent(stickId, VisionStickHistory.new);
    final prevSpeed = history.speedAt(timestamp);
    history.add(point, timestamp);
    final speed = history.speedAt(timestamp) ?? 0;

    final hit = StageHitMapper.hitTestStagePoint(
      currentOctave: currentOctave,
      point: point,
    );

    if (hit != null &&
        (prevSpeed ?? 0) >= minStrikeSpeed &&
        speed <= hoverSpeedThreshold) {
      final stickLast = _stickCooldown[stickId];
      final bellLast = _bellCooldown[hit.bellId];
      if ((stickLast == null ||
              timestamp.difference(stickLast) >=
                  AppConstants.visionStrikeCooldown) &&
          (bellLast == null ||
              timestamp.difference(bellLast) >=
                  AppConstants.visionStrikeCooldown)) {
        final peak = history.peakSpeed() ?? prevSpeed ?? minStrikeSpeed;
        final intensity = ((peak - minStrikeSpeed) /
                (AppConstants.visionMaxStrikeSpeed - minStrikeSpeed))
            .clamp(0.35, 1.0);
        _currentBatch.add(
          VisionStrikeHitResult(
            bellId: hit.bellId,
            region: hit.region,
            intensity: intensity,
            stickId: stickId,
          ),
        );
        _batchStart ??= timestamp;
        _stickCooldown[stickId] = timestamp;
        _bellCooldown[hit.bellId] = timestamp;
      }
    }

    return _maybeFlushBatch(timestamp);
  }

  List<VisionStrikeHitResult> _maybeFlushBatch(DateTime timestamp) {
    if (_currentBatch.isEmpty || _batchStart == null) return const [];
    if (timestamp.difference(_batchStart!) >=
        AppConstants.visionSimultaneousWindow) {
      final results = List<VisionStrikeHitResult>.from(_currentBatch);
      _currentBatch.clear();
      _batchStart = null;
      return results;
    }
    return const [];
  }

  StickMotionState motionStateForStick(int stickId) {
    final history = _histories[stickId];
    if (history == null || history.length < 2) return StickMotionState.idle;
    final speed = history.speedAt(DateTime.now()) ?? 0;
    if (speed >= minStrikeSpeed) return StickMotionState.striking;
    if (speed > hoverSpeedThreshold) return StickMotionState.hovering;
    return StickMotionState.idle;
  }

  double? currentSpeedForStick(int stickId) {
    return _histories[stickId]?.speedAt(DateTime.now());
  }
}
