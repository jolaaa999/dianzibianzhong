import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/sensor_data.dart';
import '../models/song_library.dart';
import '../models/song_model.dart';
import '../providers/app_provider.dart';
import '../widgets/stage_bianzhong_view.dart';
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
      body: const _PerformancePage(),
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

            return Stack(
              children: [
                Padding(
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
                      ninjaMode: provider.ninjaMode,
                      bladeTrails: provider.bladeTrails,
                      followAlongCurrentBellId: provider.followAlongCurrentBellId,
                      followAlongNotePulse: provider.followProgress.notePulse,
                      onBellTapped: provider.onBellTapped,
                    ),
                  ),
                ),
                if (provider.isFollowAlongActive || provider.followProgress.state == FollowAlongState.finished)
                  Positioned(
                    top: verticalPadding + 8,
                    left: horizontalPadding + 8,
                    right: horizontalPadding + 8,
                    child: _FollowAlongOverlay(provider: provider),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FollowAlongOverlay extends StatelessWidget {
  final AppProvider provider;
  const _FollowAlongOverlay({required this.provider});

  @override
  Widget build(BuildContext context) {
    final progress = provider.followProgress;

    if (progress.state == FollowAlongState.countdown) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${provider.countdownRemaining}',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '秒后开始',
              style: TextStyle(fontSize: 20, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
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
    final isFinished = provider.followProgress.state == FollowAlongState.finished;
    return _ModeChip(
      label: isActive ? '跟奏中' : (isFinished ? '已完成' : '智能跟奏'),
      icon: Icons.music_note,
      isActive: isActive || isFinished,
      activeColor: Colors.amber,
      onTap: () {
        if (isActive || isFinished) {
          provider.stopFollowAlong();
        } else {
          _showSongSelectionDialog(context, provider);
        }
      },
    );
  }
}

void _showSongSelectionDialog(BuildContext context, AppProvider provider) {
  final songs = SongLibrary.songs;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('选择歌曲'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(song.title),
              subtitle: Text('${song.artist} · ${song.notes.length}个音符'),
              trailing: const Icon(Icons.play_circle_fill),
              onTap: () {
                Navigator.of(ctx).pop();
                provider.startFollowAlong(song.id);
              },
            );
          },
        ),
      ),
    ),
  );
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
