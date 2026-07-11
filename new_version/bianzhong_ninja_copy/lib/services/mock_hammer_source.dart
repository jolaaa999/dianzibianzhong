import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'udp_hammer_service.dart';

/// 离线 / 演示模式下的击锤合成器。
///
/// 通过 [`UdpHammerService.injectRawPayload`] 注入合成 UDP 数据，从而让
/// 完整的 [_handleUdpMessage] 决策通路在无硬件时也能跑通。
///
/// 用法：
///   flutter run -d windows --dart-define=MOCK=swinger
class MockHammerSource {
  final UdpHammerService service;
  final Random _rng;
  final int maxHammers;
  Timer? _timer;
  final Duration _cursorInterval;
  bool _isRunning = false;
  String scenario;

  MockHammerSource({
    required this.service,
    this.maxHammers = 2,
    this.scenario = 'idle',
    Duration cursorInterval = const Duration(milliseconds: 33),
    int? seed,
  })  : _rng = Random(seed ?? 12345),
        _cursorInterval = cursorInterval;

  bool get isRunning => _isRunning;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _timer = Timer.periodic(_cursorInterval, _onTick);
  }

  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  void setScenario(String newScenario) {
    scenario = newScenario;
  }

  int _nowUs() => DateTime.now().microsecondsSinceEpoch;

  String _cursorPayload({
    required int hammerId,
    required String deviceId,
    required double yaw,
    required double pitch,
    required double roll,
  }) {
    final timestamp = _nowUs();
    return jsonEncode({
      'proto': 1,
      'type': 'cursor',
      'id': hammerId,
      'deviceId': deviceId,
      'yaw': yaw,
      'pitch': pitch,
      'roll': roll,
      'quaternion': {'w': 1.0, 'x': 0.0, 'y': 0.0, 'z': 0.0},
      'octave': 3,
      'timestamp': timestamp,
    });
  }

  String _strikePayload({
    required int hammerId,
    required String deviceId,
    required double force,
    required double yaw,
    required double pitch,
    required double roll,
    required String tier,
  }) {
    final timestamp = _nowUs();
    return jsonEncode({
      'proto': 1,
      'type': 'strike',
      'id': hammerId,
      'deviceId': deviceId,
      'force': force,
      'tier': tier,
      'yaw': yaw,
      'pitch': pitch,
      'roll': roll,
      'quaternion': {'w': 1.0, 'x': 0.0, 'y': 0.0, 'z': 0.0},
      'octave': 3,
      'timestamp': timestamp,
    });
  }

  void _onTick(Timer timer) {
    if (!_isRunning) return;
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;

    for (int id = 1; id <= maxHammers; id++) {
      final deviceId = 'MOCK-AABBCC$id';
      final yaw = sin(t * 0.7 + id) * 18.0;
      final pitch = (cos(t * 0.5 + id) * 16.0) - 4.0;
      final roll = sin(t * 0.3 + id) * 6.0;
      service.injectRawPayload(_cursorPayload(
        hammerId: id,
        deviceId: deviceId,
        yaw: yaw,
        pitch: pitch,
        roll: roll,
      ));

      // swinger 场景：每 ~2.5s 给第一支发一次 strike
      if (scenario == 'swinger' && id == 1 && _rng.nextDouble() < 0.02) {
        final force = 0.4 + _rng.nextDouble() * 0.5;
        final tier = force > 0.75
            ? 'heavy'
            : (force > 0.55 ? 'medium' : 'light');
        service.injectRawPayload(_strikePayload(
          hammerId: 1,
          deviceId: 'MOCK-AABBCC1',
          force: force,
          yaw: yaw,
          pitch: pitch,
          roll: roll,
          tier: tier,
        ));
      }
    }
  }
}
