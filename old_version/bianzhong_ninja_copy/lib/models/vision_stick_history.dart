import 'dart:ui' show Offset;

class VisionStickSample {
  final Offset point;
  final DateTime time;

  const VisionStickSample(this.point, this.time);
}

/// 每根敲击棒坐标历史环形缓冲
class VisionStickHistory {
  static const int maxLength = 8;
  final List<VisionStickSample> _samples = [];

  void add(Offset point, DateTime time) {
    _samples.add(VisionStickSample(point, time));
    while (_samples.length > maxLength) {
      _samples.removeAt(0);
    }
  }

  void clear() => _samples.clear();

  int get length => _samples.length;

  VisionStickSample? get latest => _samples.isEmpty ? null : _samples.last;

  VisionStickSample? get previous =>
      _samples.length >= 2 ? _samples[_samples.length - 2] : null;

  /// 最近两帧归一化速度（单位/秒）
  double? speedAt(DateTime now) {
    if (_samples.length < 2) return null;
    final prev = _samples[_samples.length - 2];
    final curr = _samples.last;
    final dtMs = curr.time.difference(prev.time).inMilliseconds;
    if (dtMs <= 0) return null;
    final dtSec = dtMs / 1000.0;
    final dist = (curr.point - prev.point).distance;
    return dist / dtSec;
  }

  double? peakSpeed() {
    if (_samples.length < 2) return null;
    double peak = 0;
    for (int i = 1; i < _samples.length; i++) {
      final dtMs = _samples[i].time.difference(_samples[i - 1].time).inMilliseconds;
      if (dtMs <= 0) continue;
      final dist = (_samples[i].point - _samples[i - 1].point).distance;
      peak = dist / (dtMs / 1000.0) > peak ? dist / (dtMs / 1000.0) : peak;
    }
    return peak;
  }
}
