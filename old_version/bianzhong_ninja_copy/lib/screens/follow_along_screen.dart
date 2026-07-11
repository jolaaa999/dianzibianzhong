import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song_library.dart';
import '../models/song_model.dart';
import '../providers/app_provider.dart';
import '../widgets/stage_bianzhong_view.dart';

class FollowAlongScreen extends StatelessWidget {
  const FollowAlongScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('智能跟奏')),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isFollowAlongActive ||
              provider.followProgress.state == FollowAlongState.paused) {
            return _PlayingView(provider: provider);
          }
          if (provider.followProgress.state == FollowAlongState.finished) {
            return _ResultView(provider: provider);
          }
          return _SongListView(provider: provider);
        },
      ),
    );
  }
}

class _SongListView extends StatelessWidget {
  final AppProvider provider;

  const _SongListView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final songs = SongLibrary.songs;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _startSong(context, song.id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${song.artist}  ♩=${song.bpm}  ${song.notes.length}个音符',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.play_circle_fill,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _startSong(BuildContext context, String songId) {
    provider.startFollowAlong(songId);
  }
}

class _PlayingView extends StatelessWidget {
  final AppProvider provider;

  const _PlayingView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final progress = provider.followProgress;
    final song = provider.currentSong;
    final isCountdown = progress.state == FollowAlongState.countdown;
    final isPaused = progress.state == FollowAlongState.paused;
    final isPlaying = progress.state == FollowAlongState.playing;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            song?.title ?? '',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            song?.artist ?? '',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          if (isCountdown)
            Expanded(
              child: Center(
                child: Text(
                  '${provider.countdownRemaining}',
                  style: TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),

          if (isPlaying || isPaused) ...[
            Expanded(
              child: StageBianzhongView(
                currentOctave: provider.currentOctave,
                lastStrikeBellId: provider.lastStrikeBellId,
                activeBellIds: provider.activeBellIds,
                activeHammers: provider.activeHammers,
                hammerSensorStates: provider.activeHammerSensorStates,
                stickFrames: provider.stickFrames,
                followAlongCurrentBellId: provider.followAlongCurrentBellId,
                followAlongNotePulse: progress.notePulse,
                onBellTapped: provider.onBellTapped,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: song == null
                  ? 0
                  : (progress.currentNoteIndex + 1) / song.notes.length,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard(
                  label: '进度',
                  value:
                      '${progress.currentNoteIndex + 1}/${progress.totalNotes}',
                  icon: Icons.music_note,
                ),
                _StatCard(
                  label: '命中',
                  value: '${progress.hitCount}',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
                _StatCard(
                  label: '未中',
                  value: '${progress.missCount}',
                  icon: Icons.cancel,
                  color: Colors.red,
                ),
                _StatCard(
                  label: '准确率',
                  value:
                      '${(progress.accuracy * 100).toStringAsFixed(0)}%',
                  icon: Icons.percent,
                  color: Colors.blue,
                ),
              ],
            ),

            if (progress.currentNoteIndex >= 0 &&
                song != null &&
                progress.currentNoteIndex < song.notes.length)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _CurrentNoteDisplay(
                  note: song.notes[progress.currentNoteIndex],
                ),
              ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isPaused)
                  FloatingActionButton.large(
                    heroTag: 'resume',
                    onPressed: provider.resumeFollowAlong,
                    child: const Icon(Icons.play_arrow),
                  )
                else
                  FloatingActionButton.large(
                    heroTag: 'pause',
                    onPressed: provider.pauseFollowAlong,
                    child: const Icon(Icons.pause),
                  ),
                const SizedBox(width: 24),
                FloatingActionButton.large(
                  heroTag: 'stop',
                  onPressed: provider.stopFollowAlong,
                  backgroundColor: Colors.red[400],
                  child: const Icon(Icons.stop),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

class _CurrentNoteDisplay extends StatelessWidget {
  final SongNote note;

  const _CurrentNoteDisplay({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber, width: 2),
      ),
      child: Column(
        children: [
          const Text(
            '请敲击',
            style: TextStyle(fontSize: 14, color: Colors.amber),
          ),
          const SizedBox(height: 8),
          Text(
            note.displayLabel,
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: Colors.amber,
            ),
          ),
          Text(
            note.note,
            style: const TextStyle(fontSize: 16, color: Colors.amber),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Icon(icon, color: effectiveColor, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: effectiveColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  final AppProvider provider;

  const _ResultView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final progress = provider.followProgress;
    final accuracy = (progress.accuracy * 100).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
          const SizedBox(height: 24),
          const Text(
            '演奏完成!',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatCard(
                label: '命中',
                value: '${progress.hitCount}',
                icon: Icons.check_circle,
                color: Colors.green,
              ),
              _StatCard(
                label: '未中',
                value: '${progress.missCount}',
                icon: Icons.cancel,
                color: Colors.red,
              ),
              _StatCard(
                label: '准确率',
                value: '$accuracy%',
                icon: Icons.percent,
                color: double.parse(accuracy) >= 80
                    ? Colors.green
                    : double.parse(accuracy) >= 50
                        ? Colors.orange
                        : Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 48),
          FilledButton.icon(
            onPressed: () {
              provider.stopFollowAlong();
            },
            icon: const Icon(Icons.replay),
            label: const Text('返回曲库'),
          ),
        ],
      ),
    );
  }
}
