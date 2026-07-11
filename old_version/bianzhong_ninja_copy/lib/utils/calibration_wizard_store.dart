import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/calibration_state.dart';

/// 校准向导进度持久化（支持中断恢复）
class CalibrationWizardStore {
  static const _prefsKey = 'calibration_wizard_state';

  static Future<CalibrationState?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CalibrationState.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(CalibrationState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
