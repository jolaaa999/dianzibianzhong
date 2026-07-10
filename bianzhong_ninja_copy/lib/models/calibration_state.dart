/// 校准向导步骤
enum CalibrationStep {
  cameraConfirm,
  stickDetection,
  mappingVerify,
}

/// 校准状态
class CalibrationState {
  final CalibrationStep step;
  final bool leftVerified;
  final bool rightVerified;
  final int verifiedBellCount;
  final int totalBellsToVerify;

  const CalibrationState({
    this.step = CalibrationStep.cameraConfirm,
    this.leftVerified = false,
    this.rightVerified = false,
    this.verifiedBellCount = 0,
    this.totalBellsToVerify = 12,
  });

  bool get sticksReady => leftVerified && rightVerified;
  bool get isComplete => verifiedBellCount >= totalBellsToVerify;

  CalibrationState copyWith({
    CalibrationStep? step,
    bool? leftVerified,
    bool? rightVerified,
    int? verifiedBellCount,
    int? totalBellsToVerify,
  }) {
    return CalibrationState(
      step: step ?? this.step,
      leftVerified: leftVerified ?? this.leftVerified,
      rightVerified: rightVerified ?? this.rightVerified,
      verifiedBellCount: verifiedBellCount ?? this.verifiedBellCount,
      totalBellsToVerify: totalBellsToVerify ?? this.totalBellsToVerify,
    );
  }
}
