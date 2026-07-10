/// 舞台编钟布局统一配置（视觉渲染与碰撞检测共用）
class StageBellLayout {
  final String note;
  final double x;
  final double y;
  final bool isUpper;
  final double visualScale;

  const StageBellLayout({
    required this.note,
    required this.x,
    required this.y,
    required this.isUpper,
    required this.visualScale,
  });

  /// 当前八度下 12 个钟面布局（归一化坐标 0~1）
  static const List<StageBellLayout> bells = [
    StageBellLayout(note: 'C', x: 0.10, y: 0.78, isUpper: false, visualScale: 1.10),
    StageBellLayout(note: 'D', x: 0.23, y: 0.78, isUpper: false, visualScale: 1.06),
    StageBellLayout(note: 'E', x: 0.36, y: 0.78, isUpper: false, visualScale: 1.02),
    StageBellLayout(note: 'F', x: 0.50, y: 0.78, isUpper: false, visualScale: 1.00),
    StageBellLayout(note: 'G', x: 0.64, y: 0.78, isUpper: false, visualScale: 0.97),
    StageBellLayout(note: 'A', x: 0.77, y: 0.78, isUpper: false, visualScale: 0.94),
    StageBellLayout(note: 'B', x: 0.90, y: 0.78, isUpper: false, visualScale: 0.92),
    StageBellLayout(note: 'C#', x: 0.25, y: 0.27, isUpper: true, visualScale: 1.12),
    StageBellLayout(note: 'D#', x: 0.375, y: 0.27, isUpper: true, visualScale: 1.04),
    StageBellLayout(note: 'F#', x: 0.50, y: 0.27, isUpper: true, visualScale: 0.96),
    StageBellLayout(note: 'G#', x: 0.625, y: 0.27, isUpper: true, visualScale: 0.88),
    StageBellLayout(note: 'A#', x: 0.75, y: 0.27, isUpper: true, visualScale: 0.80),
  ];
}
