/// 校准向导步骤
enum CalibrationStep {
  cameraConfirm,
  stickDetection,
  mappingVerify,
}

/// 校准状态（支持中断恢复）
class CalibrationState {
  final CalibrationStep step;
  final bool leftVerified;
  final bool rightVerified;
  final int verifiedBellCount;
  final int totalBellsToVerify;
  final int? highlightBellId;

  const CalibrationState({
    this.step = CalibrationStep.cameraConfirm,
    this.leftVerified = false,
    this.rightVerified = false,
    this.verifiedBellCount = 0,
    this.totalBellsToVerify = 12,
    this.highlightBellId,
  });

  bool get sticksReady => leftVerified && rightVerified;
  bool get isComplete => verifiedBellCount >= totalBellsToVerify;

  CalibrationState copyWith({
    CalibrationStep? step,
    bool? leftVerified,
    bool? rightVerified,
    int? verifiedBellCount,
    int? totalBellsToVerify,
    int? highlightBellId,
    bool clearHighlightBellId = false,
  }) {
    return CalibrationState(
      step: step ?? this.step,
      leftVerified: leftVerified ?? this.leftVerified,
      rightVerified: rightVerified ?? this.rightVerified,
      verifiedBellCount: verifiedBellCount ?? this.verifiedBellCount,
      totalBellsToVerify: totalBellsToVerify ?? this.totalBellsToVerify,
      highlightBellId: clearHighlightBellId
          ? null
          : (highlightBellId ?? this.highlightBellId),
    );
  }

  Map<String, dynamic> toJson() => {
    'step': step.index,
    'leftVerified': leftVerified,
    'rightVerified': rightVerified,
    'verifiedBellCount': verifiedBellCount,
    'totalBellsToVerify': totalBellsToVerify,
    'highlightBellId': highlightBellId,
  };

  factory CalibrationState.fromJson(Map<String, dynamic> json) {
    final stepIndex = (json['step'] as num?)?.toInt() ?? 0;
    final safeStep = CalibrationStep.values[stepIndex.clamp(
      0,
      CalibrationStep.values.length - 1,
    )];
    return CalibrationState(
      step: safeStep,
      leftVerified: json['leftVerified'] == true,
      rightVerified: json['rightVerified'] == true,
      verifiedBellCount: (json['verifiedBellCount'] as num?)?.toInt() ?? 0,
      totalBellsToVerify: (json['totalBellsToVerify'] as num?)?.toInt() ?? 12,
      highlightBellId: (json['highlightBellId'] as num?)?.toInt(),
    );
  }
}
