import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import '../utils/constants.dart';

class _ActiveVoice {
  final int bellId;
  final DateTime startedAt;
  final AudioPlayer player;
  final bool isReverbLayer;

  _ActiveVoice({
    required this.bellId,
    required this.startedAt,
    required this.player,
    this.isReverbLayer = false,
  });
}

/// 音频服务（含多音 3dB 衰减、简化 DRC 与厅堂混响）
class AudioService {
  static const int _polyphonyPoolSize = 16;

  final List<AudioPlayer> _players = [];
  final List<_ActiveVoice> _activeVoices = [];
  final Map<int, String> _assetOverrides = {};
  int _nextPlayerIndex = 0;
  double _volume = AppConstants.defaultVolume;
  bool _isEnabled = true;
  bool _reverbEnabled = true;
  Duration _reverbDelay = AppConstants.audioReverbDelay;
  double _reverbWetMix = AppConstants.audioReverbWetMix;
  int _reverbMinVoices = AppConstants.audioReverbMinVoices;

  double get volume => _volume;
  bool get isEnabled => _isEnabled;
  bool get reverbEnabled => _reverbEnabled;
  Duration get reverbDelay => _reverbDelay;
  double get reverbWetMix => _reverbWetMix;
  int get reverbMinVoices => _reverbMinVoices;
  int get activeVoiceCount =>
      _activeVoices.where((voice) => !voice.isReverbLayer).length;
  Map<int, String> get assetOverrides => Map.unmodifiable(_assetOverrides);

  void setBellAssetOverride(int bellId, String assetFileName) {
    if (bellId < 1 || bellId > AppConstants.bellCount) return;
    _assetOverrides[bellId] = assetFileName;
  }

  void clearBellAssetOverride(int bellId) {
    _assetOverrides.remove(bellId);
  }

  void clearAllBellAssetOverrides() {
    _assetOverrides.clear();
  }

  AudioService() {
    _initializePlayers();
  }

  void _initializePlayers() {
    for (int voice = 0; voice < _polyphonyPoolSize; voice++) {
      final player = AudioPlayer();
      player.setVolume(_volume);
      player.onPlayerComplete.listen((_) => _removeVoiceForPlayer(player));
      _players.add(player);
    }
    developer.log(
      '音频播放器已初始化，声部池大小: $_polyphonyPoolSize',
      name: 'AudioService',
    );
  }

  void _removeVoiceForPlayer(AudioPlayer player) {
    _activeVoices.removeWhere((v) => v.player == player);
  }

  AudioPlayer _acquirePlayer() {
    final player = _players[_nextPlayerIndex % _players.length];
    _nextPlayerIndex = (_nextPlayerIndex + 1) % _players.length;
    return player;
  }

  /// 返回从调用到 `play()` 完成的毫秒数（音频启动延迟参考）
  Future<int> playBell(int bellId, double intensity) async {
    if (!_isEnabled || bellId < 1 || bellId > AppConstants.bellCount) {
      return 0;
    }

    final started = DateTime.now();
    try {
      if (_players.isEmpty) return 0;
      final player = _acquirePlayer();

      final bell = BellMapping.getBellById(bellId);
      final n = activeVoiceCount + 1;
      final gainCompensation = math.pow(10, -3 * (n - 1) / 20).toDouble();
      var adjustedVolume = _volume * intensity * gainCompensation;

      if (n >= 2) {
        final masterGain = (1.0 / math.sqrt(n)).clamp(0.35, 1.0);
        adjustedVolume *= masterGain;
      }

      final assetFileName =
          _assetOverrides[bellId] ?? BellMapping.resolveAssetFileName(bell);
      final assetPath = 'audio/$assetFileName';
      final dryVolume = adjustedVolume.clamp(0.0, 1.0);

      _activeVoices.add(
        _ActiveVoice(
          bellId: bellId,
          startedAt: DateTime.now(),
          player: player,
        ),
      );

      await player.setVolume(dryVolume);
      await player.play(AssetSource(assetPath));

      if (_reverbEnabled && n >= _reverbMinVoices) {
        _scheduleReverbTail(
          bellId: bellId,
          assetPath: assetPath,
          dryVolume: dryVolume,
        );
      }

      return DateTime.now().difference(started).inMilliseconds;
    } catch (e) {
      developer.log('播放音效失败: $e', name: 'AudioService', error: e);
      return DateTime.now().difference(started).inMilliseconds;
    }
  }

  void _scheduleReverbTail({
    required int bellId,
    required String assetPath,
    required double dryVolume,
  }) {
    final reverbPlayer = _acquirePlayer();
    final wetVolume = (dryVolume * _reverbWetMix).clamp(0.05, 0.42);

    Future.delayed(_reverbDelay, () async {
      if (!_isEnabled) return;
      try {
        _activeVoices.add(
          _ActiveVoice(
            bellId: bellId,
            startedAt: DateTime.now(),
            player: reverbPlayer,
            isReverbLayer: true,
          ),
        );
        await reverbPlayer.setVolume(wetVolume);
        await reverbPlayer.play(AssetSource(assetPath));
      } catch (e) {
        developer.log('混响层播放失败: $e', name: 'AudioService', error: e);
      }
    });
  }

  void configureReverb({
    Duration? delay,
    double? wetMix,
    int? minVoices,
  }) {
    if (delay != null) {
      _reverbDelay = delay;
    }
    if (wetMix != null) {
      _reverbWetMix = wetMix.clamp(0.05, 0.6);
    }
    if (minVoices != null) {
      _reverbMinVoices = minVoices.clamp(2, 8);
    }
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  void setReverbEnabled(bool enabled) {
    _reverbEnabled = enabled;
  }

  Future<void> stopAll() async {
    for (final player in _players) {
      await player.stop();
    }
    _activeVoices.clear();
  }

  void dispose() {
    for (final player in _players) {
      player.dispose();
    }
    _players.clear();
    _activeVoices.clear();
    _nextPlayerIndex = 0;
  }
}

/// 音频生成器（用于生成编钟音色）
class AudioGenerator {
  static List<double> generateBellTone({
    required double frequency,
    required double duration,
    required double sampleRate,
    double intensity = 1.0,
  }) {
    final samples = (duration * sampleRate).toInt();
    final data = List<double>.filled(samples, 0.0);

    final fundamental = frequency;
    final harmonics = [
      (fundamental, 1.0),
      (fundamental * 2.0, 0.5),
      (fundamental * 3.0, 0.3),
      (fundamental * 4.5, 0.2),
      (fundamental * 6.0, 0.15),
    ];

    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final envelope = intensity * (1.0 - t / duration) * (1.0 - t / duration);
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

class Math {
  static const double pi = 3.14159265359;

  static double sin(double x) {
    double result = 0;
    double term = x;
    for (int n = 1; n <= 10; n++) {
      result += term;
      term *= -x * x / ((2 * n) * (2 * n + 1));
    }
    return result;
  }
}
