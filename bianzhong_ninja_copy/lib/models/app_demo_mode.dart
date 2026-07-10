/// 展厅演示模式
enum DemoMode {
  standby,
  performing,
}

extension DemoModeExtension on DemoMode {
  String get displayName => switch (this) {
    DemoMode.standby => '待机',
    DemoMode.performing => '演奏',
  };
}

/// 输入模式
enum InputMode {
  imu,
  vision,
  touchOnly,
}

extension InputModeExtension on InputMode {
  String get displayName => switch (this) {
    InputMode.imu => 'IMU 击锤 (UDP)',
    InputMode.vision => '视觉追踪 (WebSocket)',
    InputMode.touchOnly => '仅触控 (调试)',
  };
}
