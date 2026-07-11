/// 应用常量定义
class AppConstants {
  // UDP 硬件输入
  static const int defaultUdpPort = 3333;
  static const Duration hammerTimeout = Duration(seconds: 3);
  static const int maxHammerCount = 12;

  // WebSocket 兼容模式
  static const String defaultWsUrl = 'ws://192.168.4.1:81';
  static const String defaultSsid = 'Bianzhong_Stage';
  static const String defaultPassword = '12345678';
  static const String bleProvisionPrefix = 'BianzhongHammer-';
  static const String bleProofOfPossession = '12345678';

  // 连接配置
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const Duration heartbeatInterval = Duration(seconds: 5);

  // 编钟配置
  static const int bellCount = 60;
  static const int minOctave = 1;
  static const int maxOctave = 5;
  static const int defaultOctave = 3;
  static const double yawMin = -180.0;
  static const double yawMax = 180.0;
  static const double upperLayerPitchThreshold = 15.0;

  static const List<String> lowerLayerNotes = [
    'C',
    'D',
    'E',
    'F',
    'G',
    'A',
    'B',
  ];

  static const List<String> upperLayerNotes = ['C#', 'D#', 'F#', 'G#', 'A#'];

  // 音频配置
  static const double defaultVolume = 0.8;
  static const double defaultSensitivity = 0.6;

  // UI 配置
  static const double bellSize = 50.0;
  static const double bellSpacing = 8.0;
  static const double minUiStrikeIntensity = 0.12;
  static const Duration uiStrikeDebounce = Duration(milliseconds: 180);
  static const Duration bellHighlightDuration = Duration(milliseconds: 300);
  static const Duration stageRefreshInterval = Duration(milliseconds: 33);
  static const Duration sideStrikeHoverLockDelay = Duration(seconds: 1);

  // 忍者模式配置
  static const int bladeTrailMaxLength = 24;
  static const double slashAngularVelocityThreshold = 100.0;
  static const double slashForceAngularVelocity = 200.0;
  static const Duration slashTrailFadeDuration = Duration(milliseconds: 350);
  static const double bladeTrailWidth = 4.0;
  static const double bladeTrailGlowWidth = 12.0;
  static const double trailHitMinSegmentLength = 0.008;
  static const Duration comboWindow = Duration(milliseconds: 600);
}

/// 编钟音高映射（5 个八度，60 个 bellId）
class BellMapping {
  static const List<String> pitchClasses = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static const List<String> availableAssets = [
    'bell_a.wav',
    'bell_a1.wav',
    'bell_a2.wav',
    'bell_a3.wav',
    'bell_b.wav',
    'bell_b1.wav',
    'bell_b2.wav',
    'bell_bcc.wav',
    'bell_c.wav',
    'bell_c1.wav',
    'bell_c2.wav',
    'bell_c3.wav',
    'bell_c4.wav',
    'bell_d.wav',
    'bell_d1.wav',
    'bell_d1k.wav',
    'bell_d2.wav',
    'bell_d3.wav',
    'bell_d4.wav',
    'bell_e.wav',
    'bell_e1.wav',
    'bell_e2.wav',
    'bell_e3.wav',
    'bell_f1.wav',
    'bell_f2.wav',
    'bell_f3.wav',
    'bell_f3k.wav',
    'bell_g.wav',
    'bell_g1.wav',
    'bell_g2.wav',
    'bell_g3.wav',
    'bell_gk.wav',
    'bell_sharp_a.wav',
    'bell_sharp_a1.wav',
    'bell_sharp_a2.wav',
    'bell_sharp_c2.wav',
    'bell_sharp_c3.wav',
    'bell_sharp_d1.wav',
    'bell_sharp_d2.wav',
    'bell_sharp_d3.wav',
    'bell_sharp_f.wav',
    'bell_sharp_f1.wav',
    'bell_sharp_f2.wav',
    'bell_sharp_f3.wav',
    'bell_sharp_g.wav',
    'bell_sharp_g1.wav',
    'bell_sharp_g2.wav',
    'bell_sharp_g3.wav',
    'bell_大字组 5 di.wav',
    'bell_大字组 b3.wav',
    'bell_大字组1 3.wav',
  ];

  static final List<BellNote> bells = [
    for (
      int octave = AppConstants.minOctave;
      octave <= AppConstants.maxOctave;
      octave++
    )
      for (int index = 0; index < pitchClasses.length; index++)
        BellNote(
          id: (octave - 1) * pitchClasses.length + index + 1,
          note: pitchClasses[index],
          octave: octave,
        ),
  ];

  static final Set<String> _assetSet = availableAssets.toSet();
  static final Map<String, int> _noteIndex = {
    for (int index = 0; index < pitchClasses.length; index++)
      pitchClasses[index]: index,
  };

  static BellNote getBellById(int id) {
    final safeId = id.clamp(1, bells.length);
    return bells[safeId - 1];
  }

  static BellNote? getBellByNote(String note, int octave) {
    final bellId = getBellId(octave, note);
    if (bellId == null) return null;
    return getBellById(bellId);
  }

  static List<BellNote> getBellsByOctave(int octave) {
    return bells.where((bell) => bell.octave == octave).toList();
  }

  static int? getBellId(int octave, String note) {
    final noteIndex = _noteIndex[note];
    if (noteIndex == null) return null;
    final safeOctave = octave.clamp(
      AppConstants.minOctave,
      AppConstants.maxOctave,
    );
    return (safeOctave - 1) * pitchClasses.length + noteIndex + 1;
  }

  static String resolveAssetFileName(BellNote bell) {
    for (final candidate in _assetCandidatesFor(bell.note, bell.octave)) {
      if (_assetSet.contains(candidate)) {
        return candidate;
      }
    }
    return 'bell_c3.wav';
  }

  static Iterable<String> _assetCandidatesFor(String note, int octave) sync* {
    final token = _assetTokenFor(note);

    yield 'bell_$token$octave.wav';
    if (octave == 4) {
      yield 'bell_$token.wav';
    }

    final nearbyOctaves = <int>[
      for (int offset = 1; offset <= 4; offset++) ...[
        if (octave - offset >= AppConstants.minOctave) octave - offset,
        if (octave + offset <= AppConstants.maxOctave) octave + offset,
      ],
    ];

    for (final nearbyOctave in nearbyOctaves) {
      yield 'bell_$token$nearbyOctave.wav';
      if (nearbyOctave == 4) {
        yield 'bell_$token.wav';
      }
    }

    // 兼容少量历史命名
    switch (note) {
      case 'B':
        yield 'bell_bcc.wav';
        yield 'bell_大字组 b3.wav';
        break;
      case 'D':
        yield 'bell_d1k.wav';
        break;
      case 'F':
        yield 'bell_f3k.wav';
        break;
      case 'G':
        yield 'bell_gk.wav';
        break;
      case 'C#':
        yield 'bell_大字组 5 di.wav';
        break;
      case 'E':
        yield 'bell_大字组1 3.wav';
        break;
    }
  }

  static String _assetTokenFor(String note) {
    if (note.contains('#')) {
      return 'sharp_${note[0].toLowerCase()}';
    }
    return note.toLowerCase();
  }

  static int transposeBellId(int bellId, int semitoneOffset) {
    final bell = getBellById(bellId);
    final startIndex = ((bell.octave - 1) * pitchClasses.length) +
        (_noteIndex[bell.note] ?? 0);
    final shiftedIndex = (startIndex + semitoneOffset).clamp(0, bells.length - 1);
    return bells[shiftedIndex].id;
  }

  static int nextTwoScaleStepsBellId(int bellId) {
    final bell = getBellById(bellId);
    final (nextNote, octaveOffset) = switch (bell.note) {
      'C' => ('E', 0),
      'C#' => ('F', 0),
      'D' => ('F', 0),
      'D#' => ('G', 0),
      'E' => ('G', 0),
      'F' => ('A', 0),
      'F#' => ('A#', 0),
      'G' => ('B', 0),
      'G#' => ('C', 1),
      'A' => ('C', 1),
      'A#' => ('D', 1),
      'B' => ('D', 1),
      _ => (bell.note, 0),
    };

    final nextOctave = (bell.octave + octaveOffset).clamp(
      AppConstants.minOctave,
      AppConstants.maxOctave,
    );
    return getBellId(nextOctave, nextNote) ?? bellId;
  }
}

/// 编钟音符数据
class BellNote {
  final int id;
  final String note;
  final int octave;

  const BellNote({required this.id, required this.note, required this.octave});

  String get label => '$note$octave';
}
