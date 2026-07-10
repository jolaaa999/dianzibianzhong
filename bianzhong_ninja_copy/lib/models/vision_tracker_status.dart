/// 视觉追踪服务状态（来自 Python OpenCV 服务）
class VisionTrackerStatus {
  final int threshold;
  final bool calibrating;
  final double calibrationProgress;
  final int fps;
  final int detectedSticks;
  final DateTime updatedAt;

  const VisionTrackerStatus({
    required this.threshold,
    this.calibrating = false,
    this.calibrationProgress = 1.0,
    this.fps = 30,
    this.detectedSticks = 0,
    required this.updatedAt,
  });

  factory VisionTrackerStatus.fromJson(Map<String, dynamic> json) {
    return VisionTrackerStatus(
      threshold: (json['threshold'] as num?)?.toInt() ?? 220,
      calibrating: json['calibrating'] as bool? ?? false,
      calibrationProgress:
          ((json['calibration_progress'] ?? 1.0) as num).toDouble(),
      fps: (json['fps'] as num?)?.toInt() ?? 30,
      detectedSticks: (json['detected_sticks'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.now(),
    );
  }

  String get summary {
    if (calibrating) {
      return '阈值校准中 ${(calibrationProgress * 100).toStringAsFixed(0)}%';
    }
    return '阈值 $threshold · 识别 $detectedSticks/2 棒 · ${fps}fps';
  }
}
