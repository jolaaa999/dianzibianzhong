import '../utils/constants.dart';

enum SongNoteRegion { center, left, right }

class SongNote {
  final String note;
  final int octave;
  final double beats;
  final SongNoteRegion region;

  const SongNote({
    required this.note,
    this.octave = 3,
    this.beats = 1.0,
    this.region = SongNoteRegion.center,
  });

  int? get bellId => BellMapping.getBellId(octave, note);

  String get displayLabel => switch (note) {
        'C' => '1',
        'C#' => '#1',
        'D' => '2',
        'D#' => '#2',
        'E' => '3',
        'F' => '4',
        'F#' => '#4',
        'G' => '5',
        'G#' => '#5',
        'A' => '6',
        'A#' => '#6',
        'B' => '7',
        _ => note,
      };
}

class Song {
  final String id;
  final String title;
  final String artist;
  final int bpm;
  final List<SongNote> notes;
  final int defaultOctave;

  const Song({
    required this.id,
    required this.title,
    this.artist = '',
    required this.bpm,
    required this.notes,
    this.defaultOctave = 3,
  });

  double get beatDurationMs => 60000.0 / bpm;

  Duration noteDuration(int noteIndex) {
    return Duration(milliseconds: (notes[noteIndex].beats * beatDurationMs).round());
  }

  Duration totalDuration() {
    double totalBeats = 0;
    for (final n in notes) {
      totalBeats += n.beats;
    }
    return Duration(milliseconds: (totalBeats * beatDurationMs).round());
  }
}

enum FollowAlongState {
  idle,
  countdown,
  playing,
  paused,
  finished,
}

class FollowAlongProgress {
  final int currentNoteIndex;
  final FollowAlongState state;
  final Duration elapsed;
  final int hitCount;
  final int missCount;
  final int totalNotes;
  final int notePulse;

  const FollowAlongProgress({
    this.currentNoteIndex = -1,
    this.state = FollowAlongState.idle,
    this.elapsed = Duration.zero,
    this.hitCount = 0,
    this.missCount = 0,
    this.totalNotes = 0,
    this.notePulse = 0,
  });

  double get accuracy => totalNotes == 0 ? 0.0 : hitCount / totalNotes;

  FollowAlongProgress copyWith({
    int? currentNoteIndex,
    FollowAlongState? state,
    Duration? elapsed,
    int? hitCount,
    int? missCount,
    int? totalNotes,
    int? notePulse,
  }) {
    return FollowAlongProgress(
      currentNoteIndex: currentNoteIndex ?? this.currentNoteIndex,
      state: state ?? this.state,
      elapsed: elapsed ?? this.elapsed,
      hitCount: hitCount ?? this.hitCount,
      missCount: missCount ?? this.missCount,
      totalNotes: totalNotes ?? this.totalNotes,
      notePulse: notePulse ?? this.notePulse,
    );
  }
}
