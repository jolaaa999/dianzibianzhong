import 'dart:convert';
import 'dart:math' as math;

/// 传感器数据模型
class SensorData {
  final Quaternion quaternion;
  final Vector3 acceleration;
  final Vector3 gyroscope;
  final bool strike;
  final double intensity;
  final int? octave;
  final int? bellId;
  final int? hammerId;
  final int? seatIndex;
  final String? deviceId;
  final String? hand;
  final double? yaw;
  final double? pitch;
  final double? roll;
  final double? stageX;
  final double? stageY;
  final DateTime timestamp;

  SensorData({
    required this.quaternion,
    required this.acceleration,
    required this.gyroscope,
    required this.strike,
    required this.intensity,
    this.octave,
    this.bellId,
    this.hammerId,
    this.seatIndex,
    this.deviceId,
    this.hand,
    this.yaw,
    this.pitch,
    this.roll,
    this.stageX,
    this.stageY,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      quaternion: Quaternion.fromJson(
        json['quaternion'] as Map<String, dynamic>?,
      ),
      acceleration: Vector3.fromJson(
        (json['acceleration'] ?? json['linear_acceleration'])
            as Map<String, dynamic>?,
      ),
      gyroscope: Vector3.fromJson(json['gyroscope'] as Map<String, dynamic>?),
      strike: json['strike'] ?? false,
      intensity: (json['intensity'] ?? 0.0).toDouble(),
      octave: (json['octave'] as num?)?.toInt(),
      bellId: (json['bellId'] as num?)?.toInt(),
      hammerId: ((json['hammerId'] ?? json['id']) as num?)?.toInt(),
      seatIndex: (json['seatIndex'] as num?)?.toInt(),
      deviceId: json['deviceId'] as String?,
      hand: json['hand'] as String?,
      yaw: (json['yaw'] as num?)?.toDouble(),
      pitch: (json['pitch'] as num?)?.toDouble(),
      roll: (json['roll'] as num?)?.toDouble(),
      stageX: (json['stageX'] as num?)?.toDouble(),
      stageY: (json['stageY'] as num?)?.toDouble(),
    );
  }

  factory SensorData.fromUdpHammer({
    required int hammerId,
    required double yaw,
    required double pitch,
    required double roll,
    Quaternion? quaternion,
    required bool strike,
    required double intensity,
    double? stageX,
    double? stageY,
    int? bellId,
    int? octave,
    int? timestampUs,
    int? seatIndex,
    String? deviceId,
    String? hand,
  }) {
    final timestamp = timestampUs == null
        ? DateTime.now()
        : DateTime.fromMicrosecondsSinceEpoch(timestampUs);
    return SensorData(
      quaternion: quaternion ?? const Quaternion.identity(),
      acceleration: Vector3.zero(),
      gyroscope: Vector3.zero(),
      strike: strike,
      intensity: intensity,
      octave: octave,
      bellId: bellId,
      hammerId: hammerId,
      seatIndex: seatIndex,
      deviceId: deviceId,
      hand: hand,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      stageX: stageX,
      stageY: stageY,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quaternion': quaternion.toJson(),
      'acceleration': acceleration.toJson(),
      'gyroscope': gyroscope.toJson(),
      'strike': strike,
      'intensity': intensity,
      'octave': octave,
      'bellId': bellId,
      'hammerId': hammerId,
      'seatIndex': seatIndex,
      'deviceId': deviceId,
      'hand': hand,
      'yaw': yaw,
      'pitch': pitch,
      'roll': roll,
      'stageX': stageX,
      'stageY': stageY,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}

class EulerAngles {
  final double yaw;
  final double pitch;
  final double roll;

  const EulerAngles({
    required this.yaw,
    required this.pitch,
    required this.roll,
  });
}

/// 四元数
class Quaternion {
  final double w;
  final double x;
  final double y;
  final double z;

  Quaternion({
    required this.w,
    required this.x,
    required this.y,
    required this.z,
  });

  const Quaternion.identity() : w = 1.0, x = 0.0, y = 0.0, z = 0.0;

  factory Quaternion.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    return Quaternion(
      w: (value['w'] ?? 1.0).toDouble(),
      x: (value['x'] ?? 0.0).toDouble(),
      y: (value['y'] ?? 0.0).toDouble(),
      z: (value['z'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'w': w, 'x': x, 'y': y, 'z': z};
  }

  bool get isIdentityLike =>
      (w - 1.0).abs() < 1e-6 &&
      x.abs() < 1e-6 &&
      y.abs() < 1e-6 &&
      z.abs() < 1e-6;

  double get magnitude => math.sqrt((w * w) + (x * x) + (y * y) + (z * z));

  Quaternion normalized() {
    final mag = magnitude;
    if (mag <= 1e-9) {
      return const Quaternion.identity();
    }
    return Quaternion(
      w: w / mag,
      x: x / mag,
      y: y / mag,
      z: z / mag,
    );
  }

  Quaternion conjugated() {
    return Quaternion(w: w, x: -x, y: -y, z: -z);
  }

  Quaternion multiplied(Quaternion other) {
    return Quaternion(
      w: (w * other.w) - (x * other.x) - (y * other.y) - (z * other.z),
      x: (w * other.x) + (x * other.w) + (y * other.z) - (z * other.y),
      y: (w * other.y) - (x * other.z) + (y * other.w) + (z * other.x),
      z: (w * other.z) + (x * other.y) - (y * other.x) + (z * other.w),
    );
  }

  Vector3 rotateVector(Vector3 vector) {
    final pure = Quaternion(w: 0.0, x: vector.x, y: vector.y, z: vector.z);
    final rotated = multiplied(pure).multiplied(conjugated());
    return Vector3(x: rotated.x, y: rotated.y, z: rotated.z);
  }

  double angleToDegrees(Quaternion other) {
    final left = normalized();
    final right = other.normalized();
    final dot =
        ((left.w * right.w) +
                (left.x * right.x) +
                (left.y * right.y) +
                (left.z * right.z))
            .abs()
            .clamp(0.0, 1.0);
    return 2.0 * math.acos(dot) * 57.2957795;
  }

  EulerAngles toEulerDegrees() {
    final sinrCosp = 2.0 * ((w * x) + (y * z));
    final cosrCosp = 1.0 - (2.0 * ((x * x) + (y * y)));
    final roll = math.atan2(sinrCosp, cosrCosp);

    final sinp = 2.0 * ((w * y) - (z * x));
    final pitch = sinp.abs() >= 1.0
        ? math.pi / 2.0 * sinp.sign
        : math.asin(sinp);

    final sinyCosp = 2.0 * ((w * z) + (x * y));
    final cosyCosp = 1.0 - (2.0 * ((y * y) + (z * z)));
    final yaw = math.atan2(sinyCosp, cosyCosp);

    return EulerAngles(
      yaw: yaw * 57.2957795,
      pitch: pitch * 57.2957795,
      roll: roll * 57.2957795,
    );
  }
}

/// 三维向量
class Vector3 {
  final double x;
  final double y;
  final double z;

  Vector3({required this.x, required this.y, required this.z});

  const Vector3.zero() : x = 0.0, y = 0.0, z = 0.0;

  factory Vector3.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    return Vector3(
      x: (value['x'] ?? 0.0).toDouble(),
      y: (value['y'] ?? 0.0).toDouble(),
      z: (value['z'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'x': x, 'y': y, 'z': z};
  }

  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

/// WebSocket消息模型
class WebSocketMessage {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  WebSocketMessage({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory WebSocketMessage.fromJson(String jsonStr) {
    final json = jsonDecode(jsonStr);
    return WebSocketMessage(type: json['type'] ?? 'unknown', data: json);
  }

  String toJson() {
    return jsonEncode({
      'type': type,
      ...data,
      'timestamp': timestamp.millisecondsSinceEpoch,
    });
  }

  // 创建触摸事件消息
  factory WebSocketMessage.touchEvent({
    required int bellId,
    required double intensity,
  }) {
    return WebSocketMessage(
      type: 'touch',
      data: {'bellId': bellId, 'intensity': intensity},
    );
  }

  // 创建触觉反馈消息
  factory WebSocketMessage.hapticEvent({
    required int effect,
    required double intensity,
  }) {
    return WebSocketMessage(
      type: 'haptic',
      data: {'effect': effect, 'intensity': intensity},
    );
  }

  // 创建ping消息
  factory WebSocketMessage.ping() {
    return WebSocketMessage(type: 'ping', data: {});
  }
}

/// 连接状态枚举
enum ConnectionStatus {
  disconnected,
  listening,
  connecting,
  connected,
  reconnecting,
  error,
}

extension ConnectionStatusExtension on ConnectionStatus {
  String get displayName {
    switch (this) {
      case ConnectionStatus.disconnected:
        return '未连接';
      case ConnectionStatus.listening:
        return '监听中';
      case ConnectionStatus.connecting:
        return '连接中...';
      case ConnectionStatus.connected:
        return '已连接';
      case ConnectionStatus.reconnecting:
        return '重新连接中...';
      case ConnectionStatus.error:
        return '连接错误';
    }
  }

  bool get isConnected => this == ConnectionStatus.connected;
}
