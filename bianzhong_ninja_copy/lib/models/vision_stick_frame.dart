import 'dart:convert';

/// 视觉追踪敲击棒帧数据
class VisionStickFrame {
  final int stickId;
  final double x;
  final double y;
  final double confidence;
  final DateTime timestamp;
  final bool isVisible;

  const VisionStickFrame({
    required this.stickId,
    required this.x,
    required this.y,
    required this.confidence,
    required this.timestamp,
    this.isVisible = true,
  });

  factory VisionStickFrame.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'];
    DateTime timestamp;
    if (ts is int) {
      timestamp = ts > 1e12
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    } else if (ts is double) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    } else {
      timestamp = DateTime.now();
    }

    final visible = json['visible'];
    return VisionStickFrame(
      stickId: (json['stick_id'] ?? json['stickId'] ?? 1) as int,
      x: ((json['x'] ?? 0.0) as num).toDouble().clamp(0.0, 1.0),
      y: ((json['y'] ?? 0.0) as num).toDouble().clamp(0.0, 1.0),
      confidence: ((json['confidence'] ?? 1.0) as num).toDouble().clamp(0.0, 1.0),
      timestamp: timestamp,
      isVisible: visible is bool ? visible : true,
    );
  }

  factory VisionStickFrame.lost({required int stickId}) {
    return VisionStickFrame(
      stickId: stickId,
      x: 0,
      y: 0,
      confidence: 0,
      timestamp: DateTime.now(),
      isVisible: false,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': 'stick_frame',
    'stick_id': stickId,
    'x': x,
    'y': y,
    'confidence': confidence,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'visible': isVisible,
  };

  static VisionStickFrame? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final type = json['type'] as String?;
      if (type != null && type != 'stick_frame') return null;
      return VisionStickFrame.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
