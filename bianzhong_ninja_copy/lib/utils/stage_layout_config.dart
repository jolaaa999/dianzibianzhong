import 'dart:math' as math;

/// 编钟角色：主编钟（音域核心）/ 辅编钟（扩展音域）
enum BellRole {
  primary,
  auxiliary,
}

/// 舞台编钟布局统一配置（视觉渲染与碰撞检测共用）
class StageBellLayout {
  final String note;
  final double x;
  final double y;
  final bool isUpper;
  final BellRole role;
  final double visualScale;

  const StageBellLayout({
    required this.note,
    required this.x,
    required this.y,
    required this.isUpper,
    required this.role,
    required this.visualScale,
  });

  bool get isPrimary => role == BellRole.primary;

  /// 半弧形阵列：下层 7 个主编钟 + 上层 5 个辅编钟
  static final List<StageBellLayout> bells = _buildSemiArcLayout();

  static List<StageBellLayout> _buildSemiArcLayout() {
    const primaryNotes = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    const auxiliaryNotes = ['C#', 'D#', 'F#', 'G#', 'A#'];

    final primary = _layoutArc(
      notes: primaryNotes,
      role: BellRole.primary,
      isUpper: false,
      centerX: 0.50,
      centerY: 0.74,
      radiusX: 0.40,
      radiusY: 0.10,
      startAngle: math.pi * 1.12,
      endAngle: math.pi * 1.88,
      baseScale: 1.08,
    );

    final auxiliary = _layoutArc(
      notes: auxiliaryNotes,
      role: BellRole.auxiliary,
      isUpper: true,
      centerX: 0.50,
      centerY: 0.34,
      radiusX: 0.30,
      radiusY: 0.08,
      startAngle: math.pi * 1.20,
      endAngle: math.pi * 1.80,
      baseScale: 0.86,
    );

    return [...primary, ...auxiliary];
  }

  static List<StageBellLayout> _layoutArc({
    required List<String> notes,
    required BellRole role,
    required bool isUpper,
    required double centerX,
    required double centerY,
    required double radiusX,
    required double radiusY,
    required double startAngle,
    required double endAngle,
    required double baseScale,
  }) {
    final count = notes.length;
    final results = <StageBellLayout>[];

    for (var i = 0; i < count; i++) {
      final t = count == 1 ? 0.5 : i / (count - 1);
      final angle = startAngle + (endAngle - startAngle) * t;
      final centerWeight = 1.0 - (t - 0.5).abs() * 0.35;
      final scale = baseScale * (0.92 + centerWeight * 0.08);

      results.add(
        StageBellLayout(
          note: notes[i],
          x: (centerX + radiusX * math.cos(angle)).clamp(0.06, 0.94),
          y: (centerY + radiusY * math.sin(angle)).clamp(0.12, 0.92),
          isUpper: isUpper,
          role: role,
          visualScale: scale,
        ),
      );
    }

    return results;
  }
}
