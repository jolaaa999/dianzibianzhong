import 'dart:async';
import 'dart:developer' as developer;
import 'package:audioplayers/audioplayers.dart';
import '../utils/constants.dart';

/// 音频服务
class AudioService {
  static const int _polyphonyPoolSize = 16;

  final List<AudioPlayer> _players = [];
  int _nextPlayerIndex = 0;
  double _volume = AppConstants.defaultVolume;
  bool _isEnabled = true;

  double get volume => _volume;
  bool get isEnabled => _isEnabled;

  AudioService() {
    _initializePlayers();
  }

  /// 初始化音频播放器
  void _initializePlayers() {
    for (int voice = 0; voice < _polyphonyPoolSize; voice++) {
      final player = AudioPlayer();
      player.setVolume(_volume);
      _players.add(player);
    }
    developer.log(
      '音频播放器已初始化，声部池大小: $_polyphonyPoolSize',
      name: 'AudioService',
    );
  }

  /// 播放编钟音效（极简路径，不调音量避免阻塞）
  void playBell(int bellId, double intensity) {
    if (!_isEnabled || bellId < 1 || bellId > AppConstants.bellCount) return;
    if (_players.isEmpty) return;

    final player = _players[_nextPlayerIndex % _players.length];
    _nextPlayerIndex = (_nextPlayerIndex + 1) % _players.length;

    final assetFileName = BellMapping.resolveAssetFileName(
        BellMapping.getBellById(bellId));
    player.play(AssetSource('audio/$assetFileName'));
  }

  /// 设置音量
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    for (final player in _players) {
      player.setVolume(_volume);
    }
    developer.log('音量设置为: ${(_volume * 100).toInt()}%', name: 'AudioService');
  }

  /// 启用/禁用音频
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    developer.log('音频${enabled ? "已启用" : "已禁用"}', name: 'AudioService');
  }

  /// 停止所有播放
  Future<void> stopAll() async {
    for (final player in _players) {
      await player.stop();
    }
    developer.log('停止所有音频播放', name: 'AudioService');
  }

  /// 释放资源
  void dispose() {
    for (final player in _players) {
      player.dispose();
    }
    _players.clear();
    _nextPlayerIndex = 0;
    developer.log('音频服务已释放', name: 'AudioService');
  }
}

/// 音频生成器（用于生成编钟音色）
class AudioGenerator {
  /// 生成编钟音色的音频数据
  ///
  /// 编钟音色特点：
  /// - 基频 + 泛音
  /// - 快速衰减的包络
  /// - 金属质感
  static List<double> generateBellTone({
    required double frequency,
    required double duration,
    required double sampleRate,
    double intensity = 1.0,
  }) {
    final samples = (duration * sampleRate).toInt();
    final data = List<double>.filled(samples, 0.0);

    // 基频
    final fundamental = frequency;

    // 泛音（编钟特有的泛音结构）
    final harmonics = [
      (fundamental, 1.0), // 基频
      (fundamental * 2.0, 0.5), // 二次谐波
      (fundamental * 3.0, 0.3), // 三次谐波
      (fundamental * 4.5, 0.2), // 非整数谐波（金属特性）
      (fundamental * 6.0, 0.15), // 高次谐波
    ];

    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;

      // 包络（快速衰减）
      final envelope = intensity * (1.0 - t / duration) * (1.0 - t / duration);

      // 叠加所有谐波
      double sample = 0.0;
      for (var harmonic in harmonics) {
        final freq = harmonic.$1;
        final amp = harmonic.$2;
        sample += amp * Math.sin(2 * Math.pi * freq * t);
      }

      data[i] = sample * envelope;
    }

    return data;
  }
}

// 简单的数学工具类
class Math {
  static const double pi = 3.14159265359;

  static double sin(double x) {
    // 使用泰勒级数近似
    double result = 0;
    double term = x;
    for (int n = 1; n <= 10; n++) {
      result += term;
      term *= -x * x / ((2 * n) * (2 * n + 1));
    }
    return result;
  }
}
