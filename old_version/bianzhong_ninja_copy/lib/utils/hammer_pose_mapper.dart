import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/sensor_data.dart';

class HammerPoseProjection {
  final Offset displayPoint;
  final Offset strikePoint;
  final double relativeYawDeg;
  final double relativePitchDeg;
  final double relativeRollDeg;
  final double angularVelocity;

  const HammerPoseProjection({
    required this.displayPoint,
    required this.strikePoint,
    required this.relativeYawDeg,
    required this.relativePitchDeg,
    required this.relativeRollDeg,
    this.angularVelocity = 0.0,
  });
}

/// Relative-mode air mouse: orientation deltas drive cursor movement.
///
/// The mapper treats the hammer like a mouse rather than a laser pointer:
/// hand rotation is converted into incremental cursor movement. A dynamic
/// dead zone suppresses tremor while a higher response factor keeps fast
/// swings responsive.
class HammerPoseMapper {
  static const double _degPerScreenWidth = 46.0;
  static const double _degPerScreenHeight = 32.0;

  static const double _stillAngularVelocity = 12.0;
  static const double _slowAngularVelocity = 55.0;
  static const double _fastAngularVelocity = 260.0;
  static const double _stillDeadZoneDeg = 0.18;
  static const double _slowDeadZoneDeg = 0.08;
  static const double _fastDeadZoneDeg = 0.025;

  static const double _slowAlpha = 0.30;
  static const double _fastAlpha = 0.84;
  static const double _maxFrameDeltaDeg = 9.0;

  static const Duration _maxDeltaGap = Duration(milliseconds: 200);
  static const Duration _resetGap = Duration(milliseconds: 1500);

  final Map<String, _DeviceState> _devices = {};

  HammerPoseProjection update({
    required String deviceId,
    required Quaternion quaternion,
    required double yaw,
    required double pitch,
    required double roll,
    required DateTime timestamp,
  }) {
    final state = _devices.putIfAbsent(deviceId, _DeviceState.new);

    if (state.lastSeen != null &&
        timestamp.difference(state.lastSeen!) > _resetGap) {
      state.reset();
    }
    state.lastSeen = timestamp;

    final q = quaternion.isIdentityLike
        ? _quatFromEuler(yaw, pitch, roll)
        : quaternion.normalized();

    final pointing = _rotateForward(q);
    final az = _azimuthDeg(pointing);
    final el = _elevationDeg(pointing);

    if (state.prevAzimuth == null) {
      state.prevAzimuth = az;
      state.prevElevation = el;
      state.prevTimestamp = timestamp;
      state.cursorX = 0.5;
      state.cursorY = 0.5;
      state.smoothX = 0.5;
      state.smoothY = 0.5;

      return _buildResult(state, yaw, pitch, roll, 0.0);
    }

    final dt = timestamp.difference(state.prevTimestamp!);
    if (dt > _maxDeltaGap || dt.inMilliseconds <= 0) {
      state.prevAzimuth = az;
      state.prevElevation = el;
      state.prevTimestamp = timestamp;
      return _buildResult(state, yaw, pitch, roll, 0.0);
    }

    var deltaAz = _normalizeDeg(az - state.prevAzimuth!);
    var deltaEl = el - state.prevElevation!;
    final dtSec = dt.inMicroseconds / 1000000.0;
    final angularVelocity =
        math.sqrt((deltaAz * deltaAz) + (deltaEl * deltaEl)) / dtSec;
    final deadZone = _deadZoneFor(angularVelocity);
    final frameDelta = math.sqrt((deltaAz * deltaAz) + (deltaEl * deltaEl));
    if (frameDelta < deadZone) {
      deltaAz = 0.0;
      deltaEl = 0.0;
    } else {
      deltaAz = deltaAz.clamp(-_maxFrameDeltaDeg, _maxFrameDeltaDeg);
      deltaEl = deltaEl.clamp(-_maxFrameDeltaDeg, _maxFrameDeltaDeg);
    }

    state.cursorX = (state.cursorX! - deltaAz / _degPerScreenWidth).clamp(
      0.0,
      1.0,
    );
    state.cursorY = (state.cursorY! - deltaEl / _degPerScreenHeight).clamp(
      0.0,
      1.0,
    );

    final alpha = _alphaFor(angularVelocity);
    state.smoothX = state.smoothX! + alpha * (state.cursorX! - state.smoothX!);
    state.smoothY = state.smoothY! + alpha * (state.cursorY! - state.smoothY!);

    state.prevAzimuth = az;
    state.prevElevation = el;
    state.prevTimestamp = timestamp;

    return _buildResult(state, yaw, pitch, roll, angularVelocity);
  }

  void recenterDevice(String deviceId) {
    final state = _devices[deviceId];
    if (state == null) return;
    state.cursorX = 0.5;
    state.cursorY = 0.5;
    state.smoothX = 0.5;
    state.smoothY = 0.5;
  }

  void recenterAll() {
    for (final id in _devices.keys) {
      recenterDevice(id);
    }
  }

  void retainOnly(Set<String> activeDeviceIds) {
    _devices.removeWhere((id, _) => !activeDeviceIds.contains(id));
  }

  void clear() {
    _devices.clear();
  }

  HammerPoseProjection _buildResult(
    _DeviceState state,
    double yaw,
    double pitch,
    double roll,
    double angularVelocity,
  ) {
    final point = Offset(state.smoothX ?? 0.5, state.smoothY ?? 0.5);
    return HammerPoseProjection(
      displayPoint: point,
      strikePoint: point,
      relativeYawDeg: state.prevAzimuth ?? 0,
      relativePitchDeg: state.prevElevation ?? 0,
      relativeRollDeg: roll,
      angularVelocity: angularVelocity,
    );
  }

  static double _deadZoneFor(double angularVelocity) {
    if (angularVelocity <= _stillAngularVelocity) {
      return _stillDeadZoneDeg;
    }
    if (angularVelocity <= _slowAngularVelocity) {
      final t =
          (angularVelocity - _stillAngularVelocity) /
          (_slowAngularVelocity - _stillAngularVelocity);
      return _lerp(_stillDeadZoneDeg, _slowDeadZoneDeg, t);
    }
    final t =
        ((angularVelocity - _slowAngularVelocity) /
                (_fastAngularVelocity - _slowAngularVelocity))
            .clamp(0.0, 1.0);
    return _lerp(_slowDeadZoneDeg, _fastDeadZoneDeg, t);
  }

  static double _alphaFor(double angularVelocity) {
    final t = (angularVelocity / _fastAngularVelocity).clamp(0.0, 1.0);
    return _lerp(_slowAlpha, _fastAlpha, t);
  }

  static double _lerp(double a, double b, double t) => a + ((b - a) * t);

  static Vector3 _rotateForward(Quaternion q) {
    final w = q.w, x = q.x, y = q.y, z = q.z;
    return Vector3(
      x: 1 - 2 * (y * y + z * z),
      y: 2 * (x * y + w * z),
      z: 2 * (x * z - w * y),
    );
  }

  static double _azimuthDeg(Vector3 v) {
    return math.atan2(v.y, v.x) * 180.0 / math.pi;
  }

  static double _elevationDeg(Vector3 v) {
    final horiz = math.sqrt(v.x * v.x + v.y * v.y);
    return math.atan2(v.z, horiz) * 180.0 / math.pi;
  }

  static Quaternion _quatFromEuler(
    double yawDeg,
    double pitchDeg,
    double rollDeg,
  ) {
    final y = yawDeg * math.pi / 360.0;
    final p = pitchDeg * math.pi / 360.0;
    final r = rollDeg * math.pi / 360.0;
    final cy = math.cos(y), sy = math.sin(y);
    final cp = math.cos(p), sp = math.sin(p);
    final cr = math.cos(r), sr = math.sin(r);
    return Quaternion(
      w: cr * cp * cy + sr * sp * sy,
      x: sr * cp * cy - cr * sp * sy,
      y: cr * sp * cy + sr * cp * sy,
      z: cr * cp * sy - sr * sp * cy,
    );
  }

  static double _normalizeDeg(double deg) {
    var v = deg % 360.0;
    if (v > 180.0) v -= 360.0;
    if (v < -180.0) v += 360.0;
    return v;
  }
}

class _DeviceState {
  double? prevAzimuth;
  double? prevElevation;
  DateTime? prevTimestamp;
  double? cursorX;
  double? cursorY;
  double? smoothX;
  double? smoothY;
  DateTime? lastSeen;

  void reset() {
    prevAzimuth = null;
    prevElevation = null;
    prevTimestamp = null;
    cursorX = 0.5;
    cursorY = 0.5;
    smoothX = 0.5;
    smoothY = 0.5;
  }
}
