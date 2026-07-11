import 'dart:ui' show Offset;

import '../services/udp_hammer_service.dart';
import '../utils/blade_trail.dart';
import '../utils/constants.dart';
import '../utils/slash_detector.dart';
import '../utils/stage_hit_mapper.dart';

/// 单条击打决策。
///
/// 单一决策点：所有可能触发钟响 / 高亮 / 触感回传的击打事件最终归结为一个
/// [StrikeDecision] 列表，UI 与音频只负责消费本类型，不关心它来自哪条决策路径。
class StrikeDecision {
  final int bellId;
  final StageStrikeRegion region;
  final double intensity;
  final StrikeSource source;

  const StrikeDecision({
    required this.bellId,
    required this.region,
    required this.intensity,
    required this.source,
  });
}

enum StrikeSource { firmwareStrike, gestureStrike, ninjaSlash, ninjaSlashTrail }

/// 路由器输入：把"路由"逻辑可观测、可测试、无状态。
///
/// 所有跨消息可变状态（轨迹 / slash 状态机 / 上次接受击打时间）均由调用方持有，
/// 由此处的 `StrikeRouterEnv` 传入；路由器自身保持纯函数。
class StrikeRouterEnv {
  final int currentOctave;
  final Offset strikePoint;
  final StageStrikeHitResult? strikeHit;
  final bool ninjaMode;
  final double sensitivity;
  final double? previousStagePoint;
  // pre-aggregated samples from caller (this message's payload)
  final double? angularVelocity;
  // last accepted strike timestamp per device (used by caller to call .update())
  final DateTime? lastAcceptedStrikeAt;
  final DateTime timestamp;

  // mutable, owned by caller (passed in)
  BladeTrail trail;
  SlashState slashState;
  DateTime? lastAcceptedStrikeAtRef;

  StrikeRouterEnv({
    required this.currentOctave,
    required this.strikePoint,
    required this.strikeHit,
    required this.ninjaMode,
    required this.sensitivity,
    required this.previousStagePoint,
    required this.angularVelocity,
    required this.lastAcceptedStrikeAt,
    required this.timestamp,
    required this.trail,
    required this.slashState,
    required this.lastAcceptedStrikeAtRef,
  });
}

class StrikeRouter {
  StrikeRouter._();

  /// UI strike 强度阈值（直接复用 AppConstants.minUiStrikeIntensity）
  static const double _minUiStrikeIntensity = 0.12;

  /// gesture 补判常量（沿用 AppProvider 中原始逻辑，按计划收敛到此处）
  static const double _gestureMinDownwardVelocity = 0.22;
  static const double _gestureMinAngularVelocity = 105.0;
  static const double _gestureForceAngularVelocity = 180.0;
  static const Duration _gestureMinLockDuration =
      Duration(milliseconds: 55);

  /// 主路由：把「固件 strike」「应用 gesture」「忍者 slash」「忍者 slashTrail」
  /// 4 个决策源收敛为单一输出。一个消息可能产出多条决策（例如忍者模式连斩）。
  static List<StrikeDecision> route({
    required UdpHammerMessage message,
    required StrikeRouterEnv env,
  }) {
    final decisions = <StrikeDecision>[];

    final adjustedIntensity = (message.force * env.sensitivity).clamp(0.0, 1.0);
    final shouldAcceptFirmwareStrike = _shouldAcceptFirmwareStrike(
      message: message,
      intensity: adjustedIntensity,
      hasHitRegion: env.strikeHit != null,
    );

    // ── 固件上行 strike ────────────────────────────────────────────
    if (shouldAcceptFirmwareStrike) {
      decisions.add(StrikeDecision(
        bellId: env.strikeHit!.bellId,
        region: env.strikeHit!.region,
        intensity: adjustedIntensity,
        source: StrikeSource.firmwareStrike,
      ));
    }

    // ── 忍者模式：推进 SlashState + 轨迹 + 斩击段命中 ──────────────
    if (env.ninjaMode && env.angularVelocity != null) {
      env.slashState.update(
        angularVelocity: env.angularVelocity!,
        currentPoint: env.strikePoint,
        previousPoint: env.previousStagePoint == null
            ? null
            : Offset(env.previousStagePoint!, env.previousStagePoint!),
        timestamp: env.timestamp,
      );
      env.trail.addPoint(
          env.strikePoint, env.timestamp, env.slashState.isSlashing);

      // 单帧「force slash」作为单条强击打（保留旧行为）
      final forceSlashHit = env.strikeHit;
      if (env.slashState.isForceSlash && forceSlashHit != null) {
        decisions.add(StrikeDecision(
          bellId: forceSlashHit.bellId,
          region: forceSlashHit.region,
          intensity: env.slashState.slashIntensity,
          source: StrikeSource.ninjaSlash,
        ));
      }

      // 斩击段扫过的全部钟体
      if (env.slashState.isSlashing) {
        final segments = env.trail.getActiveSegments();
        final trailHits = StageHitMapper.hitTestTrailSegments(
          currentOctave: env.currentOctave,
          segments: segments
              .map((s) => (
                    start: s.start,
                    end: s.end,
                    isSlashing: s.isSlashing,
                  ))
              .toList(),
        );
        for (final hit in trailHits) {
          decisions.add(StrikeDecision(
            bellId: hit.bellId,
            region: hit.region,
            intensity: env.slashState.slashIntensity,
            source: StrikeSource.ninjaSlashTrail,
          ));
        }
      }
    }

    // ── 应用 gesture 补判（仅非忍者模式）────────────────────────────
    if (!env.ninjaMode &&
        !shouldAcceptFirmwareStrike &&
        env.strikeHit != null) {
      // 仅在外部确认有 gesture signals 时调用（外部调用方负责计算 downVel 等）
      // 此处只把"是否补判"交由 caller；为避免重复，此路由器目前不重写 gesture 状态机，
      // 仅提供一个轻量入口：[resolveGestureIntensity] 由外部按上次的逻辑计算后注入。
    }

    return decisions;
  }

  /// 是否接受固件上行的 strike（强校验：必须 type=='strike' 且命中区域且强度阈值）
  static bool _shouldAcceptFirmwareStrike({
    required UdpHammerMessage message,
    required double intensity,
    required bool hasHitRegion,
  }) {
    if (!message.isStrike) return false;
    if (!hasHitRegion) return false;
    if (intensity < _minUiStrikeIntensity) return false;
    return true;
  }

  /// 应用端 gesture 补判。沿用原 `_resolveGestureStrikeIntensity` 的阈值，
  /// 但不持有任何状态——调用方需在前一帧给到 `previousStagePointY` / `previousQuaternion`。
  static double? resolveGestureIntensity({
    required StrikeHitSnapshot? previous,
    required Offset currentStrikePoint,
    required Offset? previousStrikePoint,
    required double currentAngularVelocity,
    required double? previousAngularVelocity,
    required StageStrikeHitResult? currentHit,
    required StageStrikeHitResult? previousHit,
    required DateTime timestamp,
    required DateTime? lastAcceptedStrikeAt,
  }) {
    if (currentHit == null) return null;
    final sameHit =
        previousHit != null && currentHit.bellId == previousHit.bellId;

    if (!sameHit) {
      previousHit = currentHit;
      // 重置锁时间
      previous = StrikeHitSnapshot(
        lockedAt: timestamp,
        previousHit: currentHit,
      );
    } else {
      previous ??= StrikeHitSnapshot(
        lockedAt: timestamp,
        previousHit: currentHit,
      );
    }

    final lockAgeMs =
        timestamp.difference(previous.lockedAt ?? timestamp).inMilliseconds;
    if (lockAgeMs < _gestureMinLockDuration.inMilliseconds) {
      return null;
    }
    if (lastAcceptedStrikeAt != null &&
        timestamp.difference(lastAcceptedStrikeAt) <
            AppConstants.uiStrikeDebounce) {
      return null;
    }

    final downwardVelocity = (previousStrikePoint == null)
        ? 0.0
        : (currentStrikePoint.dy - previousStrikePoint.dy) /
            (timestamp.difference(previous.lockedAt ?? timestamp).inMicroseconds /
                    1000000.0)
                .clamp(0.001, 1.0);
    final directionalHit = downwardVelocity >= _gestureMinDownwardVelocity &&
        currentAngularVelocity >= _gestureMinAngularVelocity;
    final forceHit = currentAngularVelocity >= _gestureForceAngularVelocity;
    if (!directionalHit && !forceHit) return null;

    final normalized = ((currentAngularVelocity - _gestureMinAngularVelocity) /
            (360.0 - _gestureMinAngularVelocity))
        .clamp(0.38, 1.0);
    return normalized.toDouble();
  }
}

/// 路由器外部状态包：让 `_resolveGestureStrikeIntensity` 原状态机可单测。
class StrikeHitSnapshot {
  DateTime? lockedAt;
  StageStrikeHitResult? previousHit;
  StrikeHitSnapshot({this.lockedAt, this.previousHit});
}
