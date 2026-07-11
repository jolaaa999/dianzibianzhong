/// 单次敲击延迟样本（用于 CSV 导出）
class LatencySample {
  final DateTime recordedAt;
  final int transportMs;
  final int strikeToAudioMs;
  final int totalMs;
  final int? wsRttMs;
  final int? bellId;

  const LatencySample({
    required this.recordedAt,
    required this.transportMs,
    required this.strikeToAudioMs,
    required this.totalMs,
    this.wsRttMs,
    this.bellId,
  });

  List<String> toCsvRow() => [
    recordedAt.toIso8601String(),
    '$transportMs',
    '$strikeToAudioMs',
    '$totalMs',
    wsRttMs?.toString() ?? '',
    bellId?.toString() ?? '',
  ];

  static List<String> csvHeader() => [
    'timestamp',
    'transport_ms',
    'strike_to_audio_ms',
    'total_ms',
    'ws_rtt_ms',
    'bell_id',
  ];
}
