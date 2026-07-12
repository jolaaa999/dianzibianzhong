import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/sensor_data.dart';

class HammerPoseProjection {
  final Offset displayPoint;
  final Offset strikePoint;
  final double angularVelocity;
  final bool isStriking;

  const HammerPoseProjection({
    required this.displayPoint,
    required this.strikePoint,
    this.angularVelocity = 0.0,
    this.isStriking = false,
  });
}

class HammerDeviceConfig {
  final double signX;
  final double signY;
  const HammerDeviceConfig({this.signX = 1.0, this.signY = 1.0});
}

/// 平移：倾斜绝对映射（Y 轴水平角 → 左右，X 轴倾角 → 上下）
/// 敲击：Z 轴加速度超阈值
class HammerPoseMapper {
  // 倾斜范围（度）
  static const double _tiltRangeX = 25.0;
  static const double _slowAlpha = 0.65;
  static const double _fastAlpha = 0.94;
  static const double _stillAngVel = 12.0;
  static const double _fastAngVel = 260.0;
  static const double _stillDead = 0.10;
  static const double _slowDead = 0.04;
  static const double _fastDead = 0.015;
  static const double _maxDeltaDeg = 90.0;
  // 敲击
  /// 施密特触发器：世界 Y 加速度 > 触发阈值即敲击
  static const double _strikeAccelYThreshold = 0.02;
  static const double _strikeAccelYReset = 0.005;
  /// 连续超阈值帧数确认（1=立即触发）
  static const int _strikeConfirmFrames = 1;
  /// 加速度 EMA 滤波系数（越小越平滑，0.3=平滑手抖）
  static const double _accelFilterAlpha = 0.30;
  static const Duration _strikeLock = Duration(milliseconds: 50);
  /// 敲击期间位移衰减（越大越快恢复移动）
  static const double _strikeDamping = 0.4;
  // 超时
  static const Duration _resetGap = Duration(seconds: 5);

  final Map<String, _DeviceState> _devices = {};
  final Map<String, HammerDeviceConfig> _deviceConfigs = {};
  HammerDeviceConfig _defaultConfig = const HammerDeviceConfig();

  void setDefaultConfig(HammerDeviceConfig c) => _defaultConfig = c;
  void setDeviceConfig(String id, HammerDeviceConfig c) => _deviceConfigs[id] = c;

  HammerPoseProjection update({
    required String deviceId,
    required Quaternion quaternion,
    required double yaw,
    required double pitch,
    required double roll,
    required DateTime timestamp,
    required double linearAccelX,
    required double linearAccelY,
    required double linearAccelZ,
  }) {
    final state = _devices.putIfAbsent(deviceId, _DeviceState.new);
    state.cursorX ??= 0.5; state.cursorY ??= 0.5;
    state.smoothX ??= 0.5; state.smoothY ??= 0.5;

    if (state.lastSeen != null &&
        timestamp.difference(state.lastSeen!) > _resetGap) {
      // 只重置跟踪参考系，保留光标位置
      state.prevAzimuth = null; state.prevElevation = null;
      state.filtAccelY = null; state.strikeArmed = null; state.strikeConfirmCount = null;
    }
    state.lastSeen = timestamp;
    final cfg = _deviceConfigs[deviceId] ?? _defaultConfig;

    final q = quaternion.isIdentityLike
        ? _quatFromEuler(yaw, pitch, roll)
        : quaternion.normalized();

    // ── 左右：X 轴水平角差分 ──────────────────
    // ── 上下：Z 轴世界 Y 分量差分 ──────────────
    //   worldZ.y ↑ = 锤子后仰 → 光标上移
    //   worldZ.y ↓ = 锤子前倾 → 光标下移
    final worldX = _rotateAxis(q, 1.0, 0.0, 0.0);
    final worldZ = _rotateAxis(q, 0.0, 0.0, 1.0);

    final xAxisAz = _azimuthDeg(worldX);
    final zAxisWorldY = worldZ.y; // -1..1

    double angVel = 0.0;
    if (state.prevAzimuth != null) {
      final dAz = _normDeg(xAxisAz - state.prevAzimuth!);
      final dEl = (zAxisWorldY - state.prevElevation!) * 180.0;
      angVel = math.sqrt(dAz*dAz + dEl*dEl) / 0.033;
    }

    final dead = _deadZone(angVel);
    var deltaX = _normDeg(xAxisAz - (state.prevAzimuth ?? xAxisAz));
    var deltaY = (zAxisWorldY - (state.prevElevation ?? zAxisWorldY)) * 180.0;
    if (deltaX.abs() < dead) deltaX = 0;
    if (deltaY.abs() < dead) deltaY = 0;
    deltaX = deltaX.clamp(-_maxDeltaDeg, _maxDeltaDeg);
    deltaY = deltaY.clamp(-_maxDeltaDeg, _maxDeltaDeg);
    // NaN 保护：快速挥动时四元数可能产生无效值
    if (deltaX.isNaN) deltaX = 0;
    if (deltaY.isNaN) deltaY = 0;

    final targetX = (state.cursorX! -
        deltaX / (_tiltRangeX * 0.5) * 0.5 * cfg.signX)
        .clamp(0.0, 1.0);
    final targetY = (state.cursorY! -
        deltaY / (_tiltRangeX * 0.5) * 0.5 * cfg.signY)
        .clamp(0.0, 1.0);

    // ── 敲击判定（多路径兜底）───────────────
    final wAccel = _rotateAxis(
        q, linearAccelX, linearAccelY, linearAccelZ);
    final worldAccelY = wAccel.y;
    // ① 滤波加速度
    state.filtAccelY = (state.filtAccelY ?? 0) * (1.0 - _accelFilterAlpha) +
        worldAccelY * _accelFilterAlpha;
    final filtY = state.filtAccelY!;
    if (filtY > _strikeAccelYThreshold) {
      state.strikeArmed = true;
    } else if (filtY < _strikeAccelYReset) {
      state.strikeArmed = false;
      state.strikeConfirmCount = 0;
    }
    if (state.strikeArmed == true) {
      state.strikeConfirmCount = (state.strikeConfirmCount ?? 0) + 1;
    }
    final bool accelConfirmed =
        (state.strikeConfirmCount ?? 0) >= _strikeConfirmFrames;

    // ② 原始加速度 > 0.3
    final bool rawAccelStrike = worldAccelY > 0.3;

    // ③ 总加速度 > 5 m/s²
    final double accelMag = math.sqrt(
        linearAccelX*linearAccelX + linearAccelY*linearAccelY + linearAccelZ*linearAccelZ);
    final bool magStrike = accelMag > 5.0;

    // ④ 角速度 > 25°/s
    const double _gestureAngVel = 25.0;
    final bool angVelStrike = angVel > _gestureAngVel;

    final bool isStriking =
        accelConfirmed || rawAccelStrike || magStrike || angVelStrike;
    final now = timestamp;
    if (isStriking) {
      state.strikeLockUntil = now.add(_strikeLock);
      state.strikeConfirmCount = 0;
      state.strikeArmed = false;
      state.filtAccelY = 0;
    }
    final bool locked = state.strikeLockUntil != null &&
        now.isBefore(state.strikeLockUntil!);

    if (locked) {
      // 敲击期间大幅衰减位移，减少晃动
      state.cursorX = (state.cursorX! +
          (targetX - state.cursorX!) * _strikeDamping)
          .clamp(0.0, 1.0);
      state.cursorY = (state.cursorY! +
          (targetY - state.cursorY!) * _strikeDamping)
          .clamp(0.0, 1.0);
    } else {
      state.strikeLockUntil = null;
      state.cursorX = targetX.clamp(0.0, 1.0);
      state.cursorY = targetY.clamp(0.0, 1.0);
    }

    final alpha = _alpha(angVel);
    state.smoothX = state.smoothX! + alpha * (state.cursorX! - state.smoothX!);
    state.smoothY = state.smoothY! + alpha * (state.cursorY! - state.smoothY!);

    state.prevAzimuth = xAxisAz;
    state.prevElevation = zAxisWorldY;

    return HammerPoseProjection(
      displayPoint: Offset(state.smoothX!, state.smoothY!),
      strikePoint: Offset(state.smoothX!, state.smoothY!),
      angularVelocity: angVel,
      isStriking: isStriking || locked,
    );
  }

  void recenterDevice(String id) {
    final s = _devices[id];
    if (s == null) return;
    s.cursorX=0.5; s.cursorY=0.5; s.smoothX=0.5; s.smoothY=0.5;
    s.prevAzimuth=null; s.prevElevation=null; s.strikeLockUntil=null;
    s.filtAccelY=null; s.strikeArmed=null; s.strikeConfirmCount=null;
  }
  void recenterAll() { for (final id in _devices.keys) { recenterDevice(id); } }
  void retainOnly(Set<String> ids) { _devices.removeWhere((id,_) => !ids.contains(id)); }
  void clear() { _devices.clear(); _deviceConfigs.clear(); }

  // ── 工具 ────────────────────────────────────

  static double _deadZone(double v) {
    if (v <= _stillAngVel) return _stillDead;
    if (v <= 55) return _lerp(_stillDead, _slowDead,
        (v-_stillAngVel)/(55-_stillAngVel));
    return _lerp(_slowDead, _fastDead,
        ((v-55)/(_fastAngVel-55)).clamp(0.0,1.0));
  }
  static double _alpha(double v) =>
      _lerp(_slowAlpha, _fastAlpha, (v/_fastAngVel).clamp(0.0,1.0));
  static double _lerp(double a, double b, double t) => a+(b-a)*t;

  static Vector3 _rotateAxis(Quaternion q, double ax, double ay, double az) {
    final w=q.w, x=q.x, y=q.y, z=q.z;
    return Vector3(
      x:(1-2*(y*y+z*z))*ax+(2*(x*y-w*z))*ay+(2*(x*z+w*y))*az,
      y:(2*(x*y+w*z))*ax+(1-2*(x*x+z*z))*ay+(2*(y*z-w*x))*az,
      z:(2*(x*z-w*y))*ax+(2*(y*z+w*x))*ay+(1-2*(x*x+y*y))*az,
    );
  }
  static double _azimuthDeg(Vector3 v) => math.atan2(v.y, v.x)*180.0/math.pi;
  static double _normDeg(double d) {
    var v=d%360; if(v>180)v-=360; if(v<-180)v+=360; return v;
  }
  static Quaternion _quatFromEuler(double y, double p, double r) {
    y*=math.pi/360;p*=math.pi/360;r*=math.pi/360;
    final cy=math.cos(y),sy=math.sin(y),cp=math.cos(p),sp=math.sin(p),
          cr=math.cos(r),sr=math.sin(r);
    return Quaternion(w:cr*cp*cy+sr*sp*sy, x:sr*cp*cy-cr*sp*sy,
        y:cr*sp*cy+sr*cp*sy, z:cr*cp*sy-sr*sp*cy);
  }
}

class _DeviceState {
  double? cursorX, cursorY, smoothX, smoothY;
  double? prevAzimuth, prevElevation;
  double? filtAccelY;
  bool? strikeArmed;
  int? strikeConfirmCount;
  DateTime? lastSeen, strikeLockUntil;
}
