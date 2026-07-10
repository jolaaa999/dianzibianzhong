import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';

/// 待机模式 Attract Loop 页面
class StandbyScreen extends StatefulWidget {
  const StandbyScreen({super.key});

  @override
  State<StandbyScreen> createState() => _StandbyScreenState();
}

class _StandbyScreenState extends State<StandbyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  int _messageIndex = 0;
  Timer? _messageTimer;

  static const _messages = [
    '编钟，中国古代大型打击乐器，始于西周，盛于春秋战国。',
    '「金声玉振」—— 编钟音色浑厚悠扬，被誉为「中华第一乐器」。',
    '拿起敲击棒，在屏幕前挥动，体验千年编钟的数字化演奏。',
    '双棒同时敲击，可奏出和谐的和声音效。',
    '触摸屏幕或挥动敲击棒，开始您的编钟之旅。',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _messageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff1a1410),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return CustomPaint(
                painter: _StandbyBackgroundPainter(
                  phase: _animController.value,
                ),
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 48),
                Text(
                  '虚拟数字编钟',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[200],
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Digital Bianzhong Experience',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.amber[100]?.withValues(alpha: 0.6),
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: Padding(
                    key: ValueKey(_messageIndex),
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      _messages[_messageIndex],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.6,
                        color: Colors.amber[50]?.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    context.read<AppProvider>().enterPerformingMode();
                  },
                  icon: const Icon(Icons.touch_app),
                  label: const Text('触摸屏幕开始'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StandbyBackgroundPainter extends CustomPainter {
  final double phase;

  const _StandbyBackgroundPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    for (int i = 0; i < 5; i++) {
      final angle = phase * 2 * math.pi + i * math.pi / 2.5;
      final radius = size.width * 0.12 + i * 18;
      final x = center.dx + math.cos(angle) * radius * 0.3;
      final y = center.dy + math.sin(angle) * radius * 0.15;
      final bellPaint = Paint()
        ..color = Color.lerp(
          const Color(0xff3d2b1f),
          const Color(0xff8b6914),
          0.3 + i * 0.1,
        )!
        ..style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: 40 + i * 8,
          height: 50 + i * 10,
        ),
        bellPaint,
      );
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.amber.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: size.width * 0.4),
      );
    canvas.drawCircle(center, size.width * 0.4, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _StandbyBackgroundPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}
