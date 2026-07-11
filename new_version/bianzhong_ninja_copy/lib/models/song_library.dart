import 'song_model.dart';

class SongLibrary {
  static final List<Song> songs = [
    _twinkleTwinkle,
  ];

  static Song? findById(String id) {
    for (final song in songs) {
      if (song.id == id) return song;
    }
    return null;
  }

  static const Song _twinkleTwinkle = Song(
    id: 'twinkle',
    title: '小星星',
    artist: '莫扎特',
    bpm: 80,
    defaultOctave: 3,
    notes: [
      // 第一段：一闪一闪亮晶晶
      SongNote(note: 'C', beats: 1),
      SongNote(note: 'C', beats: 1),
      SongNote(note: 'G', beats: 1),
      SongNote(note: 'G', beats: 1),
      SongNote(note: 'A', beats: 1),
      SongNote(note: 'A', beats: 1),
      SongNote(note: 'G', beats: 2),
      SongNote(note: 'F', beats: 1),
      SongNote(note: 'F', beats: 1),
      SongNote(note: 'E', beats: 1),
      SongNote(note: 'E', beats: 1),
      SongNote(note: 'D', beats: 1),
      SongNote(note: 'D', beats: 1),
      SongNote(note: 'C', beats: 2),
      // 第二段：挂在天上放光明
      SongNote(note: 'G', beats: 1),
      SongNote(note: 'G', beats: 1),
      SongNote(note: 'F', beats: 1),
      SongNote(note: 'F', beats: 1),
      SongNote(note: 'E', beats: 1),
      SongNote(note: 'E', beats: 1),
      SongNote(note: 'D', beats: 2),
      // 第三段：好像许多小眼睛
      SongNote(note: 'G', beats: 1),
      SongNote(note: 'G', beats: 1),
      SongNote(note: 'F', beats: 1),
      SongNote(note: 'F', beats: 1),
      SongNote(note: 'E', beats: 1),
      SongNote(note: 'E', beats: 1),
      SongNote(note: 'D', beats: 2),
      // 第四段：一闪一闪亮晶晶
      SongNote(note: 'C', beats: 1),
      SongNote(note: 'C', beats: 1),
      SongNote(note: 'G', beats: 1),
      SongNote(note: 'G', beats: 1),
      SongNote(note: 'A', beats: 1),
      SongNote(note: 'A', beats: 1),
      SongNote(note: 'G', beats: 2),
      SongNote(note: 'F', beats: 1),
      SongNote(note: 'F', beats: 1),
      SongNote(note: 'E', beats: 1),
      SongNote(note: 'E', beats: 1),
      SongNote(note: 'D', beats: 1),
      SongNote(note: 'D', beats: 1),
      SongNote(note: 'C', beats: 2),
    ],
  );
}
