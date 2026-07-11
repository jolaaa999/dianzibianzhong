import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 编钟网格组件（5个八度）
class BellGridWidget extends StatefulWidget {
  final Function(int bellId, double intensity) onBellTapped;
  final bool Function(int bellId) getBellState;
  final int selectedOctave;
  final ValueChanged<int> onOctaveChanged;

  const BellGridWidget({
    super.key,
    required this.onBellTapped,
    required this.getBellState,
    required this.selectedOctave,
    required this.onOctaveChanged,
  });

  @override
  State<BellGridWidget> createState() => _BellGridWidgetState();
}

class _BellGridWidgetState extends State<BellGridWidget> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bellSize = _resolveBellSize(constraints);
        final verticalGap = constraints.maxHeight < 220 ? 8.0 : 12.0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: math.max(8, constraints.maxWidth * 0.02),
            vertical: math.max(6, constraints.maxHeight * 0.04),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOctaveSelector(constraints),
              SizedBox(height: verticalGap),
              Expanded(child: _buildCurrentOctaveBells(context, bellSize)),
            ],
          ),
        );
      },
    );
  }

  /// 八度选择器
  Widget _buildOctaveSelector(BoxConstraints constraints) {
    final compact = constraints.maxWidth < 760;

    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 6.0 : 8.0,
          horizontal: compact ? 10.0 : 16.0,
        ),
        child: Row(
          children: [
            Text(
              '八度',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: compact ? 13 : 14,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (int octave = 1; octave <= 5; octave++)
                    _buildOctaveButton(octave, compact: compact),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOctaveButton(int octave, {required bool compact}) {
    final isSelected = widget.selectedOctave == octave;
    return InkWell(
      onTap: () => widget.onOctaveChanged(octave),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.amber[700]! : Colors.grey[400]!,
            width: 2,
          ),
        ),
        child: Text(
          '$octave',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.black87,
            fontSize: compact ? 12 : 14,
          ),
        ),
      ),
    );
  }

  /// 当前八度的编钟（12个音符）
  Widget _buildCurrentOctaveBells(BuildContext context, double bellSize) {
    final bells = BellMapping.getBellsByOctave(widget.selectedOctave);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 上排：C C# D D# E F (6个)
        _buildBellRow(context, bells.sublist(0, 6), bellSize),
        const SizedBox(height: 8),
        // 下排：F# G G# A A# B (6个)
        _buildBellRow(context, bells.sublist(6, 12), bellSize),
      ],
    );
  }

  Widget _buildBellRow(
    BuildContext context,
    List<BellNote> bells,
    double bellSize,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: bells
          .map((bell) => _buildBell(context, bell, bellSize))
          .toList(),
    );
  }

  Widget _buildBell(BuildContext context, BellNote bell, double bellSize) {
    final isActive = widget.getBellState(bell.id);
    final isSharp = bell.note.contains('#');
    final iconSize = bellSize * 0.42;
    final noteFontSize = bellSize * 0.18;

    return GestureDetector(
      onTap: () => widget.onBellTapped(bell.id, 0.8),
      onLongPress: () => widget.onBellTapped(bell.id, 1.0),
      child: Container(
        margin: EdgeInsets.all(bellSize * 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: bellSize,
          height: bellSize,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isActive
                  ? [Colors.amber[300]!, Colors.orange[600]!]
                  : isSharp
                  ? [Colors.grey[700]!, Colors.grey[900]!]
                  : [Colors.amber[700]!, Colors.amber[900]!],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: isActive
                    ? Colors.orange.withValues(alpha: 0.6)
                    : Colors.black.withValues(alpha: 0.3),
                blurRadius: isActive ? 12 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.notifications,
                color: Colors.white,
                size: isActive ? iconSize + 3 : iconSize,
              ),
              SizedBox(height: bellSize * 0.06),
              Text(
                bell.note,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isActive ? noteFontSize + 1 : noteFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _resolveBellSize(BoxConstraints constraints) {
    final widthBased = constraints.maxWidth / 7.6;
    final heightBased = constraints.maxHeight / 3.1;
    return math.min(widthBased, heightBased).clamp(34.0, 64.0);
  }
}
