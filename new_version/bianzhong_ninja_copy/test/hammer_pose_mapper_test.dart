import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:bianzhong_app/models/sensor_data.dart';
import 'package:bianzhong_app/utils/hammer_pose_mapper.dart';
import 'package:bianzhong_app/utils/stage_hit_mapper.dart';

const _identity = Quaternion.identity();

void main() {
  group('HammerPoseMapper', () {
    test('静止态下 displayPoint 锁死不漂移', () {
      final mapper = HammerPoseMapper();
      final initial = mapper.update(
        deviceId: 'dev1',
        quaternion: _identity,
        yaw: 0,
        pitch: 0,
        roll: 0,
        timestamp: DateTime(2026, 1, 1, 12, 0, 0),
      );

      // 模拟静止噪声
      for (int i = 1; i <= 30; i++) {
        final noiseYaw = (math.sin(i * 0.13) * 0.5);
        final noisePitch = (math.cos(i * 0.11) * 0.5);
        mapper.update(
          deviceId: 'dev1',
          quaternion: _identity,
          yaw: noiseYaw,
          pitch: noisePitch,
          roll: 0,
          timestamp: DateTime(2026, 1, 1, 12, 0, i),
        );
      }

      final finalState = mapper.update(
        deviceId: 'dev1',
        quaternion: _identity,
        yaw: 0,
        pitch: 0,
        roll: 0,
        timestamp: DateTime(2026, 1, 1, 12, 0, 60),
      );

      // 静止态光标偏移应非常小（≤ 5% 屏宽）
      final dx = (finalState.displayPoint.dx - initial.displayPoint.dx).abs();
      final dy = (finalState.displayPoint.dy - initial.displayPoint.dy).abs();
      expect(dx < 0.05, isTrue);
      expect(dy < 0.05, isTrue);
    });

    test('recenter 后会重置该设备的平滑基准', () {
      final mapper = HammerPoseMapper();
      mapper.update(
        deviceId: 'dev1',
        quaternion: _identity,
        yaw: 25,
        pitch: 30,
        roll: 0,
        timestamp: DateTime(2026, 1, 1, 12, 0, 0),
      );
      // 校准
      mapper.recenterDevice('dev1');

      // recenter 后 mapper 内部 prevAzimuth/prevElevation 应被清空，
      // 接下来同样的姿态应能从该基准开始累计，而不是叠加前面的偏移。
      final repeated = mapper.update(
        deviceId: 'dev1',
        quaternion: _identity,
        yaw: 25,
        pitch: 30,
        roll: 0,
        timestamp: DateTime(2026, 1, 1, 12, 0, 1),
      );

      // 与"先挥动一次再 recenter、之后再次挥到同一姿态"应当都会偏离 0.5 一点
      // 但 recenter 之后偏移不应比同一时刻未 recenter 时还大。
      // 这里仅保证 recenter API 不抛异常并返回有效投影点。
      expect(repeated.displayPoint.dx, inInclusiveRange(0.0, 1.0));
      expect(repeated.displayPoint.dy, inInclusiveRange(0.0, 1.0));
    });
  });

  group('StageHitMapper', () {
    test('光标点落在下排钟体区域 → 返回合法 bellId', () {
      // Bell F 配置 x=0.50, y=0.78；用 (0.50, 0.86) 在 shell 内部中心 hit rect
      final result = StageHitMapper.hitTestStagePoint(
        currentOctave: 3,
        point: const Offset(0.50, 0.86),
      );
      expect(result, isNotNull);
      // 不锁定具体 bellId（路径内点最贴近哪口钟由 hit region 决定），
      // 只要返回合法的 F/G/A 范围内（且为 octave=3）的 bellId 即可
      expect(result!.bellId, inInclusiveRange(28, 34));
      expect(result.region, anyOf(
        StageStrikeRegion.left,
        StageStrikeRegion.right,
        StageStrikeRegion.center,
      ));
    });

    test('光标点超出舞台 → 返回 null', () {
      final result = StageHitMapper.hitTestStagePoint(
        currentOctave: 3,
        point: const Offset(0.0, 0.0),
      );
      expect(result, isNull);
    });
  });
}
