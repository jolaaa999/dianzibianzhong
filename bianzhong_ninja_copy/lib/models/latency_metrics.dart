/// 客户端延迟指标（用于 PRD ≤150ms 验收参考）
class LatencyMetrics {
  final int? lastTransportMs;
  final int? lastStrikeToAudioMs;
  final int? lastClientTotalMs;
  final int? lastWsRttMs;
  final int sampleCount;
  final double avgClientTotalMs;

  const LatencyMetrics({
    this.lastTransportMs,
    this.lastStrikeToAudioMs,
    this.lastClientTotalMs,
    this.lastWsRttMs,
    this.sampleCount = 0,
    this.avgClientTotalMs = 0,
  });

  bool get meetsPrdTarget =>
      lastClientTotalMs != null && lastClientTotalMs! <= 150;

  LatencyMetrics recordStrike({
    required int transportMs,
    required int strikeToAudioMs,
  }) {
    final total = transportMs.clamp(0, 9999) + strikeToAudioMs;
    final nextCount = sampleCount + 1;
    final nextAvg =
        ((avgClientTotalMs * sampleCount) + total) / nextCount;
    return LatencyMetrics(
      lastTransportMs: transportMs,
      lastStrikeToAudioMs: strikeToAudioMs,
      lastClientTotalMs: total,
      lastWsRttMs: lastWsRttMs,
      sampleCount: nextCount,
      avgClientTotalMs: nextAvg,
    );
  }

  LatencyMetrics withWsRtt(int rttMs) {
    return LatencyMetrics(
      lastTransportMs: lastTransportMs,
      lastStrikeToAudioMs: lastStrikeToAudioMs,
      lastClientTotalMs: lastClientTotalMs,
      lastWsRttMs: rttMs,
      sampleCount: sampleCount,
      avgClientTotalMs: avgClientTotalMs,
    );
  }

  String get summary {
    if (sampleCount == 0) {
      return '尚无敲击样本';
    }
    return '最近 ${lastClientTotalMs ?? '-'}ms · '
        '平均 ${avgClientTotalMs.toStringAsFixed(0)}ms · '
        '样本 $sampleCount';
  }
}
