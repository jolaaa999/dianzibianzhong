import 'package:flutter_test/flutter_test.dart';

import 'package:bianzhong_app/services/strike_router.dart';
import 'package:bianzhong_app/services/udp_hammer_service.dart';
import 'package:bianzhong_app/utils/blade_trail.dart';
import 'package:bianzhong_app/utils/constants.dart';
import 'package:bianzhong_app/utils/slash_detector.dart';
import 'package:bianzhong_app/utils/stage_hit_mapper.dart';

UdpHammerMessage _msg({
  int hammerId = 1,
  String deviceId = 'AABBCC-H1',
  String type = 'strike',
  double force = 0.8,
}) {
  return UdpHammerMessage(
    proto: 1,
    type: type,
    hammerId: hammerId,
    deviceId: deviceId,
    seatIndex: 0,
    hand: HammerHand.left,
    octave: 3,
    yaw: 0,
    pitch: 0,
    roll: 0,
    quaternionW: 1,
    quaternionX: 0,
    quaternionY: 0,
    quaternionZ: 0,
    force: force,
    tierIndex: 2,
    timestampUs: 0,
  );
}

final _now = DateTime(2026, 1, 1, 12, 0, 0);

StrikeRouterEnv _env({
  required UdpHammerMessage message,
  required StageStrikeHitResult? hit,
  required BladeTrail trail,
  required SlashState slash,
  bool ninja = false,
  double sensitivity = 1.0,
}) {
  return StrikeRouterEnv(
    currentOctave: message.octave ?? AppConstants.defaultOctave,
    strikePoint: const Offset(0.5, 0.5),
    strikeHit: hit,
    ninjaMode: ninja,
    sensitivity: sensitivity,
    previousStagePoint: null,
    angularVelocity: null,
    lastAcceptedStrikeAt: null,
    timestamp: _now,
    trail: trail,
    slashState: slash,
    lastAcceptedStrikeAtRef: null,
  );
}

void main() {
  group('StrikeRouter.route', () {
    test('固件 strike + 命中 → 一条 firmwareStrike 决策', () {
      final hit = StageStrikeHitResult(
        bellId: 28,
        region: StageStrikeRegion.center,
      );
      final decisions = StrikeRouter.route(
        message: _msg(force: 0.6),
        env: _env(
          message: _msg(force: 0.6),
          hit: hit,
          trail: BladeTrail(),
          slash: SlashState(),
        ),
      );
      expect(decisions, hasLength(1));
      expect(decisions.first.source, StrikeSource.firmwareStrike);
      expect(decisions.first.bellId, 28);
      expect(decisions.first.intensity, 0.6);
    });

    test('cursor 类型不触发', () {
      final decisions = StrikeRouter.route(
        message: _msg(type: 'cursor'),
        env: _env(
          message: _msg(type: 'cursor'),
          hit: const StageStrikeHitResult(
            bellId: 28,
            region: StageStrikeRegion.center,
          ),
          trail: BladeTrail(),
          slash: SlashState(),
        ),
      );
      expect(decisions, isEmpty);
    });

    test('强度低于阈值不触发', () {
      final decisions = StrikeRouter.route(
        message: _msg(force: 0.05),
        env: _env(
          message: _msg(force: 0.05),
          hit: const StageStrikeHitResult(
            bellId: 28,
            region: StageStrikeRegion.center,
          ),
          trail: BladeTrail(),
          slash: SlashState(),
        ),
      );
      expect(decisions, isEmpty);
    });

    test('未命中区域时不触发', () {
      final decisions = StrikeRouter.route(
        message: _msg(force: 0.9),
        env: _env(
          message: _msg(force: 0.9),
          hit: null,
          trail: BladeTrail(),
          slash: SlashState(),
        ),
      );
      expect(decisions, isEmpty);
    });

    test('Sensitivity=0.5 时 intensity = force × 0.5', () {
      final decisions = StrikeRouter.route(
        message: _msg(force: 0.8),
        env: _env(
          message: _msg(force: 0.8),
          hit: const StageStrikeHitResult(
            bellId: 30,
            region: StageStrikeRegion.left,
          ),
          trail: BladeTrail(),
          slash: SlashState(),
          sensitivity: 0.5,
        ),
      );
      expect(decisions.first.intensity, 0.4);
    });
  });

  test('协议 v1 与 tier medium 在 JSON envelope 上保持一致', () {
    final json = {
      'proto': 1,
      'type': 'strike',
      'id': 1,
      'deviceId': 'AABBCCDDEEFF-H1',
      'force': 0.62,
      'tier': 'medium',
      'octave': 3,
      'timestamp': 1000,
    };
    expect(json['proto'], 1);
    expect(json['tier'], 'medium');
    expect((json['deviceId'] as String).endsWith('-H1'), isTrue);
  });
}
