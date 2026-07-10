import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_demo_mode.dart';
import '../models/song_model.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import '../widgets/connection_status_widget.dart';
import '../widgets/stage_bianzhong_view.dart';
import 'follow_along_screen.dart';
import 'settings_screen.dart';

/// 主界面
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('数智编钟'),
        leadingWidth: 260,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ModeButtons(),
          ),
        ),
        actions: [
          const _DemoModeActions(),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: SystemNavigator.pop,
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectionStatusWidget(),
          Expanded(
            child: Stack(
              children: const [
                _PerformancePage(),
                _FollowAlongCountdownOverlay(),
                _VisionEdgeWarningOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformancePage extends StatelessWidget {
  const _PerformancePage();

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    return ValueListenableBuilder<int>(
      valueListenable: provider.stageRevisionListenable,
      builder: (context, _, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 960 ? 12.0 : 24.0;
            final verticalPadding = constraints.maxHeight < 760 ? 10.0 : 18.0;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                verticalPadding,
                horizontalPadding,
                verticalPadding + 8,
              ),
              child: RepaintBoundary(
                child: StageBianzhongView(
                  currentOctave: provider.currentOctave,
                  lastStrikeBellId: provider.lastStrikeBellId,
                  activeBellIds: provider.activeBellIds,
                  activeHammers: provider.activeHammers,
                  hammerSensorStates: provider.activeHammerSensorStates,
                  stickFrames: provider.stickFrames,
                  ninjaMode: provider.ninjaMode,
                  bladeTrails: provider.bladeTrails,
                  followAlongCurrentBellId: provider.followAlongCurrentBellId,
                  followAlongNotePulse: provider.followProgress.notePulse,
                  debugShowHitBoxes: provider.debugShowHitBoxes,
                  onBellTapped: provider.onBellTapped,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FollowAlongCountdownOverlay extends StatelessWidget {
  const _FollowAlongCountdownOverlay();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    if (provider.followProgress.state != FollowAlongState.countdown) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 72),
          child: Text(
            '${provider.countdownRemaining}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 96,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _VisionEdgeWarningOverlay extends StatelessWidget {
  const _VisionEdgeWarningOverlay();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    if (provider.inputMode != InputMode.vision) {
      return const SizedBox.shrink();
    }

    final outOfBounds = provider.stickFrames.any((frame) {
      if (!frame.isVisible) return false;
      final inset = AppConstants.demoInteractionZoneInset;
      return frame.x < inset ||
          frame.x > 1 - inset ||
          frame.y < inset ||
          frame.y > 1 - inset;
    });

    if (!outOfBounds) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Material(
        color: Colors.orange.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            '敲击棒接近画面边缘，请回到中央操作区域',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _DemoModeActions extends StatelessWidget {
  const _DemoModeActions();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    if (!provider.demoModeEnabled ||
        provider.demoMode != DemoMode.performing) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '返回待机',
          icon: const Icon(Icons.slideshow),
          onPressed: provider.enterStandbyMode,
        ),
        IconButton(
          tooltip: '重置演示',
          icon: const Icon(Icons.restart_alt),
          onPressed: provider.resetDemoMode,
        ),
      ],
    );
  }
}

class _ModeButtons extends StatelessWidget {
  const _ModeButtons();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NinjaButton(provider: provider),
        const SizedBox(width: 6),
        _FollowAlongButton(provider: provider),
      ],
    );
  }
}

class _NinjaButton extends StatelessWidget {
  final AppProvider provider;
  const _NinjaButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isActive = provider.ninjaMode;
    return _ModeChip(
      label: '水果忍者',
      icon: Icons.flash_on,
      isActive: isActive,
      activeColor: Colors.purple,
      onTap: () => provider.ninjaMode = !isActive,
    );
  }
}

class _FollowAlongButton extends StatelessWidget {
  final AppProvider provider;
  const _FollowAlongButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isActive = provider.isFollowAlongActive;
    return _ModeChip(
      label: isActive ? '跟奏中' : '智能跟奏',
      icon: Icons.music_note,
      isActive: isActive,
      activeColor: Colors.amber,
      onTap: () {
        if (isActive) {
          provider.stopFollowAlong();
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FollowAlongScreen(),
            ),
          );
        }
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? activeColor : Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
