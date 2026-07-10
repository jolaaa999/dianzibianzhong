import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:shared_preferences/shared_preferences.dart';

/// 校准后的舞台坐标微调（全局 + 逐钟 offset，PRD 3.2.6）
class CalibrationMapping {
  static const _prefsKey = 'calibration_stage_offset';

  static Offset _globalOffset = Offset.zero;
  static final List<Offset> _globalSamples = [];
  static final Map<int, Offset> _perBellOffsets = {};
  static final Map<int, List<Offset>> _perBellSamples = {};

  static Offset get globalOffset => _globalOffset;
  static Map<int, Offset> get perBellOffsets => Map.unmodifiable(_perBellOffsets);

  static Offset adjustPoint(Offset point) => point - _globalOffset;

  static Offset adjustPointForBell(int bellId, Offset point) {
    final per = _perBellOffsets[bellId] ?? Offset.zero;
    return point - _globalOffset - per;
  }

  static void reset() {
    _globalOffset = Offset.zero;
    _globalSamples.clear();
    _perBellOffsets.clear();
    _perBellSamples.clear();
  }

  static void recordSample(Offset delta) {
    _globalSamples.add(delta);
    _recomputeGlobalOffset();
  }

  static void recordSampleForBell(int bellId, Offset delta) {
    recordSample(delta);
    final samples = _perBellSamples.putIfAbsent(bellId, () => []);
    samples.add(delta);
    _perBellOffsets[bellId] = _averageOffset(samples);
  }

  static void _recomputeGlobalOffset() {
    if (_globalSamples.isEmpty) {
      _globalOffset = Offset.zero;
      return;
    }
    _globalOffset = _averageOffset(_globalSamples);
  }

  static Offset _averageOffset(List<Offset> samples) {
    double dx = 0;
    double dy = 0;
    for (final sample in samples) {
      dx += sample.dx;
      dy += sample.dy;
    }
    return Offset(dx / samples.length, dy / samples.length);
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _globalOffset = Offset(
        ((json['dx'] ?? 0) as num).toDouble(),
        ((json['dy'] ?? 0) as num).toDouble(),
      );
      _perBellOffsets.clear();
      _perBellSamples.clear();
      final bells = json['bells'];
      if (bells is Map<String, dynamic>) {
        bells.forEach((key, value) {
          if (value is! Map<String, dynamic>) return;
          final bellId = int.tryParse(key);
          if (bellId == null) return;
          final offset = Offset(
            ((value['dx'] ?? 0) as num).toDouble(),
            ((value['dy'] ?? 0) as num).toDouble(),
          );
          _perBellOffsets[bellId] = offset;
          _perBellSamples[bellId] = [offset];
        });
      }
    } catch (_) {
      reset();
    }
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final bellsJson = <String, Map<String, double>>{};
    for (final entry in _perBellOffsets.entries) {
      bellsJson['${entry.key}'] = {
        'dx': entry.value.dx,
        'dy': entry.value.dy,
      };
    }
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'dx': _globalOffset.dx,
        'dy': _globalOffset.dy,
        'bells': bellsJson,
      }),
    );
  }

  static Future<void> clearPersisted() async {
    reset();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
