import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_demo_mode.dart';
import '../models/latency_metrics.dart';
import '../models/latency_sample.dart';
import '../models/sensor_data.dart';
import '../models/song_model.dart';
import '../models/song_library.dart';
import '../models/vision_stick_frame.dart';
import '../models/vision_tracker_status.dart';
import '../services/audio_service.dart';
import '../services/ble_provisioning_service.dart';
import '../services/udp_hammer_service.dart';
import '../services/vision_tracking_service.dart';
import '../services/wifi_info_service.dart';
import '../services/websocket_service.dart';
import '../utils/constants.dart';
import '../utils/hammer_pose_mapper.dart';
import '../utils/latency_csv_exporter.dart';
import '../utils/calibration_mapping.dart';
import '../utils/calibration_wizard_store.dart';
import '../utils/stage_hit_mapper.dart';
import '../utils/blade_trail.dart';
import '../utils/slash_detector.dart';
import '../utils/vision_strike_detector.dart';

/// 应用状态管理
class AppProvider with ChangeNotifier {
  final WebSocketService _wsService = WebSocketService();
  final UdpHammerService _udpService = UdpHammerService();
  final VisionTrackingService _visionService = VisionTrackingService();
  final VisionStrikeDetector _visionStrikeDetector = VisionStrikeDetector();
  final AudioService _audioService = AudioService();
  BleProvisioningService? _bleProvisioningService;
  final WifiInfoService _wifiInfoService = WifiInfoService();
  final HammerPoseMapper _hammerPoseMapper = HammerPoseMapper();
  final ValueNotifier<int> _stageRevision = ValueNotifier<int>(0);
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  ConnectionStatus _wsStatus = ConnectionStatus.disconnected;
  ConnectionStatus _visionStatus = ConnectionStatus.disconnected;
  InputMode _inputMode = InputMode.vision;
  String _wsUrl = AppConstants.defaultWsUrl;
  String _visionWsUrl = AppConstants.defaultVisionWsUrl;
  String _errorMessage = '';
  bool _udpListening = false;
  final Map<int, VisionStickFrame> _stickFramesById = {};
  List<ActiveHammerInfo> _activeHammers = [];
  final Map<String, SensorData> _hammerSensorDataByDeviceId = {};
  final Map<String, DateTime> _lastAcceptedStrikeAtByDeviceId = {};
  final Map<String, _HammerGestureState> _gestureStateByDeviceId = {};
  List<BleProvisionDevice> _bleDevices = [];
  bool _isBleScanning = false;
  bool _isBleProvisioning = false;
  bool _lastBleProvisionSucceeded = false;
  String _bleProvisioningMessage = '';
  String _provisioningTargetSsid = AppConstants.defaultSsid;
  String _provisioningTargetPassword = AppConstants.defaultPassword;
  String _currentWifiSsid = '';
  List<String> _nearbyWifiSsids = [];
  bool _isWifiInfoLoading = false;
  bool _isWifiScanning = false;

  SensorData? _latestSensorData;
  int _messageCount = 0;

  final Map<int, bool> _bellStates = {};
  final Map<int, Timer> _bellReleaseTimers = {};
  int? _lastStrikeBellId;
  int _currentOctave = AppConstants.defaultOctave;

  double _volume = AppConstants.defaultVolume;
  double _sensitivity = AppConstants.defaultSensitivity;
  bool _audioEnabled = true;
  bool _reverbEnabled = true;
  int _reverbDelayMs = AppConstants.audioReverbDelay.inMilliseconds;
  double _reverbWetMix = AppConstants.audioReverbWetMix;
  int _reverbMinVoices = AppConstants.audioReverbMinVoices;
  LatencyMetrics _latencyMetrics = const LatencyMetrics();
  final List<LatencySample> _latencyHistory = [];
  VisionTrackerStatus? _visionTrackerStatus;
  bool _isDisposed = false;
  DateTime? _lastStageRefreshAt;
  Timer? _stageRefreshTimer;

  bool _ninjaMode = false;
  final Map<String, BladeTrail> _bladeTrailsByDeviceId = {};
  final Map<String, SlashState> _slashStatesByDeviceId = {};

  Song? _currentSong;
  FollowAlongProgress _followProgress = const FollowAlongProgress();
  Timer? _followTimer;
  int _followElapsedMs = 0;
  final Set<int> _followHitNoteIndices = {};
  int _countdownRemaining = 0;

  DemoMode _demoMode = DemoMode.standby;
  bool _demoModeEnabled = true;
  DateTime? _lastStrikeAt;
  Timer? _demoModeTimer;
  bool _debugShowHitBoxes = false;
  bool _calibrationCompleted = false;
  bool _visionWasConnected = false;
  late final Future<void> _settingsLoadedFuture;

  ConnectionStatus get connectionStatus => _connectionStatus;
  String get wsUrl => _wsUrl;
  String get errorMessage => _errorMessage;
  String get connectionSummary => _buildConnectionSummary();
  SensorData? get latestSensorData => _latestSensorData;
  int get messageCount => _messageCount;
  int? get lastStrikeBellId => _lastStrikeBellId;
  int get currentOctave => _currentOctave;
  double get volume => _volume;
  double get sensitivity => _sensitivity;
  bool get audioEnabled => _audioEnabled;
  bool get reverbEnabled => _reverbEnabled;
  int get reverbDelayMs => _reverbDelayMs;
  double get reverbWetMix => _reverbWetMix;
  int get reverbMinVoices => _reverbMinVoices;
  LatencyMetrics get latencyMetrics => _latencyMetrics;
  List<LatencySample> get latencyHistory =>
      List.unmodifiable(_latencyHistory);
  VisionTrackerStatus? get visionTrackerStatus => _visionTrackerStatus;
  bool get isConnected => _connectionStatus.isConnected;
  bool get isMonitoringHardware => _udpListening;
  bool get isBleScanning => _isBleScanning;
  bool get isBleProvisioning => _isBleProvisioning;
  bool get lastBleProvisionSucceeded => _lastBleProvisionSucceeded;
  String get bleProvisioningMessage => _bleProvisioningMessage;
  String get provisioningTargetSsid => _provisioningTargetSsid;
  String get provisioningTargetPassword => _provisioningTargetPassword;
  String get currentWifiSsid => _currentWifiSsid;
  List<String> get nearbyWifiSsids => List.unmodifiable(_nearbyWifiSsids);
  bool get isWifiInfoLoading => _isWifiInfoLoading;
  bool get isWifiScanning => _isWifiScanning;
  List<int> get activeHammerIds =>
      _activeHammers.map((hammer) => hammer.hammerId).toList();
  List<ActiveHammerInfo> get activeHammers => List.unmodifiable(_activeHammers);
  List<SensorData> get activeHammerSensorStates {
    return _activeHammers
        .map((hammer) => _hammerSensorDataByDeviceId[hammer.deviceId])
        .whereType<SensorData>()
        .toList(growable: false);
  }

  String get activeHammerSummary => _buildActiveHammerSummary();
  List<BleProvisionDevice> get bleDevices => List.unmodifiable(_bleDevices);
  Set<int> get activeBellIds => _bellStates.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toSet();

  WebSocketService get wsService => _wsService;
  AudioService get audioService => _audioService;
  ValueListenable<int> get stageRevisionListenable => _stageRevision;
  BleProvisioningService get _bleProvisioning =>
      _bleProvisioningService ??= BleProvisioningService();

  bool get ninjaMode => _ninjaMode;
  set ninjaMode(bool value) {
    if (_ninjaMode == value) return;
    _ninjaMode = value;
    if (!value) {
      _bladeTrailsByDeviceId.clear();
      _slashStatesByDeviceId.clear();
    } else {
      if (_currentSong != null) {
        _stopFollowAlong();
      }
    }
    _notifySafely();
  }

  Map<String, BladeTrail> get bladeTrails => _bladeTrailsByDeviceId;

  Song? get currentSong => _currentSong;
  FollowAlongProgress get followProgress => _followProgress;
  bool get isFollowAlongActive =>
      _followProgress.state == FollowAlongState.playing ||
      _followProgress.state == FollowAlongState.countdown;
  int get countdownRemaining => _countdownRemaining;

  InputMode get inputMode => _inputMode;
  String get visionWsUrl => _visionWsUrl;
  ConnectionStatus get visionStatus => _visionStatus;
  bool get visionSignalLost => _visionService.isSignalLost;
  List<VisionStickFrame> get stickFrames =>
      _stickFramesById.values.toList(growable: false);
  Map<int, VisionStickFrame> get stickFramesById =>
      Map.unmodifiable(_stickFramesById);
  DemoMode get demoMode => _demoMode;
  bool get demoModeEnabled => _demoModeEnabled;
  bool get isDemoPaused => _demoMode == DemoMode.paused;
  bool get allowHardwareInput =>
      _inputMode != InputMode.touchOnly && !isDemoPaused;
  bool get allowTouchInput => !isDemoPaused;
  bool get debugShowHitBoxes => _debugShowHitBoxes;
  bool get calibrationCompleted => _calibrationCompleted;
  Future<void> get settingsLoaded => _settingsLoadedFuture;
  Future<void> waitForSettingsLoaded() => _settingsLoadedFuture;
  VisionStrikeDetector get visionStrikeDetector => _visionStrikeDetector;
  int? get followAlongCurrentBellId {
    if (_currentSong == null || _followProgress.currentNoteIndex < 0 ||
        _followProgress.currentNoteIndex >= _currentSong!.notes.length) {
      return null;
    }
    return _currentSong!.notes[_followProgress.currentNoteIndex].bellId;
  }

  void startFollowAlong(String songId) {
    final song = SongLibrary.findById(songId);
    if (song == null) return;
    _stopFollowAlong();
    if (_ninjaMode) {
      _ninjaMode = false;
      _bladeTrailsByDeviceId.clear();
      _slashStatesByDeviceId.clear();
    }
    _currentSong = song;
    _followElapsedMs = 0;
    _followHitNoteIndices.clear();
    _followProgress = FollowAlongProgress(
      state: FollowAlongState.countdown,
      totalNotes: song.notes.length,
    );
    _currentOctave = song.defaultOctave;
    _countdownRemaining = 3;
    _requestStageRefresh(immediate: true);

    _followTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdownRemaining--;
      if (_countdownRemaining <= 0) {
        timer.cancel();
        _beginFollowAlongPlayback();
      } else {
        _requestStageRefresh(immediate: true);
      }
    });
  }

  void _beginFollowAlongPlayback({bool resume = false}) {
    if (_currentSong == null) return;
    if (!resume) {
      _followProgress = _followProgress.copyWith(
        state: FollowAlongState.playing,
        currentNoteIndex: 0,
      );
      _followElapsedMs = 0;
      if (_currentSong!.notes.isNotEmpty) {
        _flashBell(_currentSong!.notes[0].bellId);
      }
    } else {
      _followProgress = _followProgress.copyWith(
        state: FollowAlongState.playing,
      );
    }
    _requestStageRefresh(immediate: true);

    final tickMs = 50;
    _followTimer = Timer.periodic(Duration(milliseconds: tickMs), (timer) {
      if (_currentSong == null ||
          _followProgress.state != FollowAlongState.playing) {
        timer.cancel();
        return;
      }

      _followElapsedMs += tickMs;

      int accumulatedMs = 0;
      int noteIndex = -1;
      for (int i = 0; i < _currentSong!.notes.length; i++) {
        accumulatedMs += _currentSong!.noteDuration(i).inMilliseconds;
        if (_followElapsedMs <= accumulatedMs) {
          noteIndex = i;
          break;
        }
      }

      if (noteIndex < 0) {
        _followProgress = const FollowAlongProgress(
          state: FollowAlongState.finished,
        );
        _currentSong = null;
        timer.cancel();
        _clearBellHighlights();
        _requestStageRefresh(immediate: true);
        return;
      }

      if (noteIndex != _followProgress.currentNoteIndex) {
        final prevIndex = _followProgress.currentNoteIndex;
        if (prevIndex >= 0 && prevIndex < _currentSong!.notes.length) {
          if (!_followHitNoteIndices.contains(prevIndex)) {
            _followProgress = _followProgress.copyWith(
              missCount: _followProgress.missCount + 1,
            );
          }
        }
        _followProgress = _followProgress.copyWith(
          currentNoteIndex: noteIndex,
          elapsed: Duration(milliseconds: _followElapsedMs),
          notePulse: _followProgress.notePulse + 1,
        );
          _flashBell(_currentSong!.notes[noteIndex].bellId);
      } else {
        _followProgress = _followProgress.copyWith(
          elapsed: Duration(milliseconds: _followElapsedMs),
        );
      }
      _requestStageRefresh(immediate: true);
    });
  }

  void _flashBell(int? bellId) {
    // Stage handles the flash via followAlongNotePulse changes
  }

  void pauseFollowAlong() {
    if (_followProgress.state != FollowAlongState.playing) return;
    _followTimer?.cancel();
    _followProgress = _followProgress.copyWith(state: FollowAlongState.paused);
    _notifySafely();
  }

  void resumeFollowAlong() {
    if (_followProgress.state != FollowAlongState.paused) return;
    _beginFollowAlongPlayback(resume: true);
  }

  void stopFollowAlong() {
    _stopFollowAlong();
    _requestStageRefresh(immediate: true);
  }

  void _stopFollowAlong() {
    _followTimer?.cancel();
    _followTimer = null;
    _currentSong = null;
    _followProgress = const FollowAlongProgress();
    _followElapsedMs = 0;
    _followHitNoteIndices.clear();
    _clearBellHighlights();
  }

  void _clearBellHighlights() {
    for (final timer in _bellReleaseTimers.values) {
      timer.cancel();
    }
    _bellReleaseTimers.clear();
    for (final bellId in _bellStates.keys) {
      _bellStates[bellId] = false;
    }
    _lastStrikeBellId = null;
  }

  void _checkFollowAlongHit(int bellId) {
    if (_currentSong == null ||
        _followProgress.state != FollowAlongState.playing ||
        _followProgress.currentNoteIndex < 0) {
      return;
    }

    final currentNote =
        _currentSong!.notes[_followProgress.currentNoteIndex];
    if (currentNote.bellId == bellId) {
      _followHitNoteIndices.add(_followProgress.currentNoteIndex);
      _followProgress = _followProgress.copyWith(
        hitCount: _followProgress.hitCount + 1,
      );
    }
  }

  AppProvider() {
    _initializeBellStates();
    _setupListeners();
    _settingsLoadedFuture = _loadPersistedSettings().then((_) => _applyInputModeStartup());
    _startDemoModeTimer();
  }

  Future<void> _applyInputModeStartup() async {
    if (_inputMode == InputMode.imu) {
      await startHardwareDiscovery();
    } else if (_inputMode == InputMode.vision) {
      await connectVisionTracking(_visionWsUrl);
    }
    _notifySafely();
  }

  Future<void> _loadPersistedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _calibrationCompleted = prefs.getBool('calibration_completed') ?? false;
      _debugShowHitBoxes = prefs.getBool('debug_show_hit_boxes') ?? false;
      _demoModeEnabled = prefs.getBool('demo_mode_enabled') ?? true;
      final savedInputMode = prefs.getString('input_mode');
      if (savedInputMode != null) {
        _inputMode = InputMode.values.firstWhere(
          (m) => m.name == savedInputMode,
          orElse: () => InputMode.vision,
        );
      }
      _visionWsUrl =
          prefs.getString('vision_ws_url') ?? AppConstants.defaultVisionWsUrl;
      _reverbEnabled = prefs.getBool('audio_reverb_enabled') ?? true;
      _reverbDelayMs =
          prefs.getInt('audio_reverb_delay_ms') ??
          AppConstants.audioReverbDelay.inMilliseconds;
      _reverbWetMix =
          prefs.getDouble('audio_reverb_wet_mix') ??
          AppConstants.audioReverbWetMix;
      _reverbMinVoices =
          prefs.getInt('audio_reverb_min_voices') ??
          AppConstants.audioReverbMinVoices;
      _audioService.setReverbEnabled(_reverbEnabled);
      _applyReverbConfig();
      _visionStrikeDetector.minStrikeSpeed =
          prefs.getDouble('vision_min_strike_speed') ??
          AppConstants.visionMinStrikeSpeed;
      _visionStrikeDetector.hoverSpeedThreshold =
          prefs.getDouble('vision_hover_speed_threshold') ??
          AppConstants.visionHoverSpeedThreshold;
      await CalibrationMapping.load();
    } catch (_) {}
  }

  Future<void> markCalibrationCompleted() async {
    _calibrationCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('calibration_completed', true);
    await CalibrationMapping.save();
    await CalibrationWizardStore.clear();
    _notifySafely();
  }

  Future<void> resetCalibration() async {
    _calibrationCompleted = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('calibration_completed', false);
    await CalibrationMapping.clearPersisted();
    await CalibrationWizardStore.clear();
    _notifySafely();
  }

  Future<void> _handleVisionHardwareDisconnect() async {
    if (!_calibrationCompleted || _inputMode != InputMode.vision) return;
    _errorMessage = '摄像头连接变化，请重新校准';
    await resetCalibration();
  }

  Future<void> setDebugShowHitBoxes(bool value) async {
    _debugShowHitBoxes = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_show_hit_boxes', value);
    _requestStageRefresh(immediate: true);
    _notifySafely();
  }

  Future<void> setReverbEnabled(bool value) async {
    _reverbEnabled = value;
    _audioService.setReverbEnabled(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('audio_reverb_enabled', value);
    _notifySafely();
  }

  Future<void> setReverbDelayMs(int value) async {
    _reverbDelayMs = value.clamp(20, 200);
    _applyReverbConfig();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('audio_reverb_delay_ms', _reverbDelayMs);
    _notifySafely();
  }

  Future<void> setReverbWetMix(double value) async {
    _reverbWetMix = value.clamp(0.05, 0.6);
    _applyReverbConfig();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('audio_reverb_wet_mix', _reverbWetMix);
    _notifySafely();
  }

  Future<void> setReverbMinVoices(int value) async {
    _reverbMinVoices = value.clamp(2, 8);
    _applyReverbConfig();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('audio_reverb_min_voices', _reverbMinVoices);
    _notifySafely();
  }

  void _applyReverbConfig() {
    _audioService.configureReverb(
      delay: Duration(milliseconds: _reverbDelayMs),
      wetMix: _reverbWetMix,
      minVoices: _reverbMinVoices,
    );
  }

  void resetLatencyMetrics() {
    _latencyMetrics = const LatencyMetrics();
    _latencyHistory.clear();
    _notifySafely();
  }

  Future<String?> exportLatencyCsv() async {
    return LatencyCsvExporter.writeToDownloads(_latencyHistory);
  }

  void setVisionThreshold(int threshold) {
    _visionService.setThreshold(threshold);
  }

  Future<void> setVisionMinStrikeSpeed(double value) async {
    _visionStrikeDetector.minStrikeSpeed = value.clamp(0.2, 3.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      'vision_min_strike_speed',
      _visionStrikeDetector.minStrikeSpeed,
    );
    _notifySafely();
  }

  Future<void> setVisionHoverSpeedThreshold(double value) async {
    _visionStrikeDetector.hoverSpeedThreshold = value.clamp(0.05, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      'vision_hover_speed_threshold',
      _visionStrikeDetector.hoverSpeedThreshold,
    );
    _notifySafely();
  }

  Future<void> setDemoModeEnabled(bool value) async {
    _demoModeEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('demo_mode_enabled', value);
    if (!value && _demoMode == DemoMode.standby) {
      enterPerformingMode();
    }
    _notifySafely();
  }

  void enterPerformingMode() {
    if (_demoMode == DemoMode.performing) return;
    _demoMode = DemoMode.performing;
    _lastStrikeAt = DateTime.now();
    _notifySafely();
  }

  void pauseDemoMode() {
    if (_demoMode != DemoMode.performing) return;
    _demoMode = DemoMode.paused;
    unawaited(_audioService.stopAll());
    _notifySafely();
  }

  void resumeDemoMode() {
    if (_demoMode != DemoMode.paused) return;
    _demoMode = DemoMode.performing;
    _lastStrikeAt = DateTime.now();
    _notifySafely();
  }

  void enterStandbyMode() {
    if (_demoMode == DemoMode.standby) return;
    _demoMode = DemoMode.standby;
    _stopFollowAlong();
    _audioService.stopAll();
    _clearBellHighlights();
    _requestStageRefresh(immediate: true);
    _notifySafely();
  }

  Future<void> resetDemoMode() async {
    await _audioService.stopAll();
    _clearBellHighlights();
    _lastStrikeAt = null;
    enterStandbyMode();
  }

  void _startDemoModeTimer() {
    _demoModeTimer?.cancel();
    _demoModeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_demoModeEnabled || _demoMode != DemoMode.performing) return;
      if (_lastStrikeAt == null) return;
      if (DateTime.now().difference(_lastStrikeAt!) >
          AppConstants.demoIdleTimeout) {
        enterStandbyMode();
      }
    });
  }

  void _onAnyStrike() {
    _lastStrikeAt = DateTime.now();
    if (_demoModeEnabled && _demoMode == DemoMode.standby) {
      enterPerformingMode();
    }
  }

  void _checkStickInteractionZone(VisionStickFrame frame) {
    if (!_demoModeEnabled || _demoMode != DemoMode.standby) return;
    if (!frame.isVisible) return;
    final inset = AppConstants.demoInteractionZoneInset;
    if (frame.x >= inset &&
        frame.x <= 1 - inset &&
        frame.y >= inset &&
        frame.y <= 1 - inset) {
      enterPerformingMode();
    }
  }

  Future<void> setInputMode(InputMode mode) async {
    if (_inputMode == mode) return;
    _inputMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('input_mode', mode.name);

    if (mode != InputMode.imu) {
      _udpService.stop();
      _udpListening = false;
    }
    if (mode != InputMode.vision) {
      await _visionService.disconnect();
      _stickFramesById.clear();
      _visionStrikeDetector.reset();
    }

    if (mode == InputMode.imu) {
      await startHardwareDiscovery();
    } else if (mode == InputMode.vision) {
      await connectVisionTracking(_visionWsUrl);
    }

    _refreshConnectionState();
    _notifySafely();
  }

  Future<void> connectVisionTracking(String url) async {
    _visionWsUrl = url;
    _inputMode = InputMode.vision;
    _errorMessage = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vision_ws_url', url);
    await prefs.setString('input_mode', InputMode.vision.name);
    await _visionService.connect(url);
    _refreshConnectionState();
    _notifySafely();
  }

  Future<void> disconnectVisionTracking() async {
    await _visionService.disconnect();
    _stickFramesById.clear();
    _visionStrikeDetector.reset();
    _refreshConnectionState();
    _notifySafely();
  }

  void requestVisionThresholdRecalibration() {
    _visionService.requestThresholdRecalibration();
  }

  void _initializeBellStates() {
    for (int i = 1; i <= AppConstants.bellCount; i++) {
      _bellStates[i] = false;
    }
  }

  void _setupListeners() {
    _subscriptions.add(
      _wsService.statusStream.listen((status) {
        _wsStatus = status;
        if (status == ConnectionStatus.error) {
          _errorMessage = 'WebSocket 连接失败，已切换为 UDP 监听模式';
        }
        _refreshConnectionState();
        _notifySafely();
      }),
    );

    _subscriptions.add(_wsService.messageStream.listen(_handleMessage));

    _subscriptions.add(_udpService.messageStream.listen(_handleUdpMessage));
    _subscriptions.add(
      _udpService.activeHammerStream.listen((hammers) {
        _activeHammers = hammers;
        final activeDeviceIds = hammers
            .map((hammer) => hammer.deviceId)
            .toSet();
        _hammerSensorDataByDeviceId.removeWhere(
          (deviceId, _) => !activeDeviceIds.contains(deviceId),
        );
        _gestureStateByDeviceId.removeWhere(
          (deviceId, _) => !activeDeviceIds.contains(deviceId),
        );
        _hammerPoseMapper.retainOnly(activeDeviceIds);
        _requestStageRefresh(immediate: true);
        _refreshConnectionState();
        _notifySafely();
      }),
    );
    _subscriptions.add(
      _udpService.errorStream.listen((error) {
        _errorMessage = 'UDP 监听失败: $error';
        _udpListening = false;
        _refreshConnectionState();
        _notifySafely();
      }),
    );

    _subscriptions.add(
      _visionService.statusStream.listen((status) {
        final previousStatus = _visionStatus;
        _visionStatus = status;
        if (status == ConnectionStatus.error) {
          _errorMessage = '视觉追踪连接失败';
        } else if (status == ConnectionStatus.connected) {
          _visionWasConnected = true;
          if (_errorMessage == '视觉追踪连接失败' ||
              _errorMessage == '追踪信号丢失') {
            _errorMessage = '';
          }
        }
        if (_inputMode == InputMode.vision &&
            _calibrationCompleted &&
            previousStatus == ConnectionStatus.connected &&
            (status == ConnectionStatus.disconnected ||
                status == ConnectionStatus.error)) {
          unawaited(_handleVisionHardwareDisconnect());
        }
        _refreshConnectionState();
        _notifySafely();
      }),
    );

    _subscriptions.add(
      _visionService.frameStream.listen(_handleVisionFrame),
    );
    _subscriptions.add(
      _visionService.rttStream.listen((rttMs) {
        _latencyMetrics = _latencyMetrics.withWsRtt(rttMs);
        _notifySafely();
      }),
    );
    _subscriptions.add(
      _visionService.trackerStatusStream.listen((status) {
        _visionTrackerStatus = status;
        _notifySafely();
      }),
    );
  }

  void _handleVisionFrame(VisionStickFrame frame) {
    if (_inputMode != InputMode.vision) return;

    final receivedAt = DateTime.now();
    _messageCount++;
    _stickFramesById[frame.stickId] = frame;

    if (!frame.isVisible) {
      _requestStageRefresh(immediate: true);
      return;
    }

    if (!isDemoPaused) {
      _checkStickInteractionZone(frame);
    }

    final point = Offset(frame.x, frame.y);

    if (_ninjaMode && !isDemoPaused) {
      _processVisionNinjaTrail(
        stickId: frame.stickId,
        point: point,
        timestamp: receivedAt,
      );
    }

    if (isDemoPaused) {
      _requestStageRefresh(immediate: true);
      return;
    }

    final hits = _visionStrikeDetector.update(
      stickId: frame.stickId,
      point: point,
      timestamp: frame.timestamp,
      currentOctave: _currentOctave,
    );

    for (final hit in hits) {
      final transportMs = receivedAt
          .difference(frame.timestamp)
          .inMilliseconds
          .clamp(0, 5000);
      _handleStrike(
        hit.intensity,
        bellId: hit.bellId,
        region: hit.region,
        transportMs: transportMs,
      );
      _visionService.sendStrikeAck(
        bellId: hit.bellId,
        stickId: hit.stickId,
      );
    }

    _requestStageRefresh(immediate: hits.isNotEmpty || _ninjaMode);
  }

  void _processVisionNinjaTrail({
    required int stickId,
    required Offset point,
    required DateTime timestamp,
  }) {
    final key = 'stick_$stickId';
    final trail = _bladeTrailsByDeviceId.putIfAbsent(key, BladeTrail.new);
    final speed = _visionStrikeDetector.currentSpeedForStick(stickId) ?? 0;
    final isSlashing = speed >= AppConstants.visionMinStrikeSpeed * 0.85;
    trail.addPoint(point, timestamp, isSlashing);

    if (!isSlashing) return;

    final segments = trail.getActiveSegments();
    final trailHits = StageHitMapper.hitTestTrailSegments(
      currentOctave: _currentOctave,
      segments: segments
          .map((s) => (start: s.start, end: s.end, isSlashing: s.isSlashing))
          .toList(),
    );
    for (final hit in trailHits) {
      _handleStrike(0.75, bellId: hit.bellId, region: hit.region);
    }
  }

  /// 启动 UDP 硬件监听
  Future<void> startHardwareDiscovery() async {
    if (_udpListening) return;

    _connectionStatus = ConnectionStatus.listening;
    _notifySafely();

    try {
      await _udpService.start();
      _udpListening = true;
      if (_errorMessage.startsWith('UDP 监听失败')) {
        _errorMessage = '';
      }
      _refreshConnectionState();
      _notifySafely();
    } catch (error) {
      _udpListening = false;
      _errorMessage = 'UDP 监听失败: $error';
      _refreshConnectionState();
      _notifySafely();
    }
  }

  Future<void> restartHardwareDiscovery() async {
    try {
      await _udpService.restart();
      _udpListening = true;
      _errorMessage = '';
    } catch (error) {
      _udpListening = false;
      _errorMessage = 'UDP 监听失败: $error';
    }
    _refreshConnectionState();
    _notifySafely();
  }

  Future<void> scanBleProvisionDevices() async {
    if (_isBleScanning) return;

    _isBleScanning = true;
    _bleProvisioningMessage = '正在扫描附近击锤蓝牙设备...';
    _notifySafely();

    try {
      final devices = await _bleProvisioning.scanDevices();
      _bleDevices = devices;
      if (devices.isEmpty) {
        _bleProvisioningMessage = '未发现可配网击锤，请确认设备已上电并靠近电脑';
      } else {
        _bleProvisioningMessage = '已发现 ${devices.length} 个可配网击锤';
      }
    } catch (error) {
      _bleDevices = [];
      _bleProvisioningMessage = '蓝牙扫描失败: $error';
    } finally {
      _isBleScanning = false;
      _notifySafely();
    }
  }

  Future<void> loadCurrentWifiSsid() async {
    if (_isWifiInfoLoading) return;

    _isWifiInfoLoading = true;
    _notifySafely();
    try {
      final ssid = await _wifiInfoService.getCurrentSsid();
      _currentWifiSsid = ssid ?? '';
      if (_currentWifiSsid.isNotEmpty &&
          (_provisioningTargetSsid.isEmpty ||
              _provisioningTargetSsid == AppConstants.defaultSsid)) {
        _provisioningTargetSsid = _currentWifiSsid;
      }
    } finally {
      _isWifiInfoLoading = false;
      _notifySafely();
    }
  }

  Future<void> scanProvisioningWifiNetworks({String? deviceId}) async {
    if (_isWifiScanning) return;

    _isWifiScanning = true;
    _bleProvisioningMessage = deviceId == null
        ? '正在扫描当前设备附近 WiFi...'
        : '正在通过击锤扫描附近 WiFi...';
    _notifySafely();

    try {
      final List<String> networks;
      if (deviceId != null && deviceId.isNotEmpty) {
        final result = await _bleProvisioning.scanWifiNetworks(
          deviceId: deviceId,
        );
        networks = result.networks;
      } else {
        networks = await _wifiInfoService.scanNearbyWifiNames();
      }

      _nearbyWifiSsids = networks;
      if (networks.isEmpty) {
        _bleProvisioningMessage = '未发现可用 WiFi，请重试';
      } else {
        _bleProvisioningMessage = '已发现 ${networks.length} 个可用 WiFi';
        if (_currentWifiSsid.isNotEmpty &&
            networks.contains(_currentWifiSsid) &&
            (_provisioningTargetSsid.isEmpty ||
                _provisioningTargetSsid == AppConstants.defaultSsid)) {
          _provisioningTargetSsid = _currentWifiSsid;
        }
      }
    } catch (error) {
      _nearbyWifiSsids = [];
      _bleProvisioningMessage = 'WiFi 扫描失败: $error';
    } finally {
      _isWifiScanning = false;
      _notifySafely();
    }
  }

  void setProvisioningTargetSsid(String ssid) {
    _provisioningTargetSsid = ssid.trim();
    _notifySafely();
  }

  void setProvisioningTargetPassword(String password) {
    _provisioningTargetPassword = password;
    _notifySafely();
  }

  Future<void> provisionBleDevice({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    if (_isBleProvisioning) return;

    _isBleProvisioning = true;
    _lastBleProvisionSucceeded = false;
    _provisioningTargetSsid = ssid;
    _provisioningTargetPassword = password;
    _bleProvisioningMessage = '正在通过蓝牙下发 WiFi 配置...';
    _notifySafely();

    try {
      final result = await _bleProvisioning.provision(
        deviceId: deviceId,
        password: password,
        ssid: ssid,
      );
      _lastBleProvisionSucceeded = result.success;
      _bleProvisioningMessage = result.message;
      if (result.success) {
        _errorMessage = '';
        await restartHardwareDiscovery();
      }
    } catch (error) {
      _lastBleProvisionSucceeded = false;
      _bleProvisioningMessage = '蓝牙配网失败: $error';
    } finally {
      _isBleProvisioning = false;
      _notifySafely();
    }
  }

  /// 兼容旧版 WebSocket 输入
  Future<void> connectLegacyWebSocket(String url) async {
    _wsUrl = url;
    _errorMessage = '';
    await _wsService.connect(url);
  }

  /// 保留旧接口，避免现有调用崩掉
  Future<void> connect(String url) async {
    await connectLegacyWebSocket(url);
  }

  /// 停止所有连接
  Future<void> disconnect() async {
    _udpService.stop();
    _udpListening = false;
    _activeHammers = [];
    _hammerSensorDataByDeviceId.clear();
    _gestureStateByDeviceId.clear();
    _hammerPoseMapper.clear();
    _lastAcceptedStrikeAtByDeviceId.clear();
    for (final timer in _bellReleaseTimers.values) {
      timer.cancel();
    }
    _bellReleaseTimers.clear();
    _requestStageRefresh(immediate: true);
    await _wsService.disconnect();
    _refreshConnectionState();
    _notifySafely();
  }

  void _handleUdpMessage(UdpHammerMessage message) {
    if (_inputMode == InputMode.vision || _inputMode == InputMode.touchOnly) {
      return;
    }
    if (isDemoPaused) return;
    _messageCount++;
    final incomingOctave = message.octave?.clamp(
      AppConstants.minOctave,
      AppConstants.maxOctave,
    );
    final effectiveOctave = incomingOctave ?? _currentOctave;
    if (incomingOctave != null && incomingOctave != _currentOctave) {
      _currentOctave = incomingOctave;
    }

    final quaternion = Quaternion(
      w: message.quaternionW,
      x: message.quaternionX,
      y: message.quaternionY,
      z: message.quaternionZ,
    );
    final timestamp = message.timestampUs == null
        ? DateTime.now()
        : DateTime.fromMicrosecondsSinceEpoch(message.timestampUs!);
    final poseProjection = _hammerPoseMapper.update(
      deviceId: message.deviceId,
      quaternion: quaternion,
      yaw: message.yaw,
      pitch: message.pitch,
      roll: message.roll,
      timestamp: timestamp,
    );

    final strikePoint = poseProjection.strikePoint;
    final strikeHit = StageHitMapper.hitTestStagePoint(
      currentOctave: effectiveOctave,
      point: strikePoint,
    );
    final bellId = strikeHit?.bellId;
    final adjustedIntensity = (message.force * _sensitivity).clamp(0.0, 1.0);
    final gestureState = _gestureStateByDeviceId.putIfAbsent(
      message.deviceId,
      _HammerGestureState.new,
    );
    final gestureStrikeIntensity = _resolveGestureStrikeIntensity(
      state: gestureState,
      deviceId: message.deviceId,
      timestamp: timestamp,
      quaternion: quaternion,
      strikePoint: strikePoint,
      strikeHit: strikeHit,
    );
    final acceptedStrike =
        _shouldAcceptUdpStrike(
          message,
          adjustedIntensity: adjustedIntensity,
          hasHitRegion: strikeHit != null,
        ) ||
        gestureStrikeIntensity != null;
    final effectiveIntensity = gestureStrikeIntensity ?? adjustedIntensity;

    if (_ninjaMode) {
      final trail = _bladeTrailsByDeviceId.putIfAbsent(
        message.deviceId,
        BladeTrail.new,
      );
      final slashState = _slashStatesByDeviceId.putIfAbsent(
        message.deviceId,
        SlashState.new,
      );
      final isSlashing = slashState.update(
        angularVelocity: poseProjection.angularVelocity,
        currentPoint: poseProjection.displayPoint,
        previousPoint: _hammerSensorDataByDeviceId[message.deviceId] != null
            ? Offset(
                _hammerSensorDataByDeviceId[message.deviceId]!.stageX ?? 0.5,
                _hammerSensorDataByDeviceId[message.deviceId]!.stageY ?? 0.5,
              )
            : null,
        timestamp: timestamp,
      );
      trail.addPoint(poseProjection.displayPoint, timestamp, isSlashing);

      if (isSlashing) {
        final segments = trail.getActiveSegments();
        final trailHits = StageHitMapper.hitTestTrailSegments(
          currentOctave: effectiveOctave,
          segments: segments
              .map((s) => (start: s.start, end: s.end, isSlashing: s.isSlashing))
              .toList(),
        );
        for (final hit in trailHits) {
          _handleStrike(
            slashState.slashIntensity,
            bellId: hit.bellId,
            region: hit.region,
          );
        }
      }
    }

    _latestSensorData = SensorData.fromUdpHammer(
      hammerId: message.hammerId,
      seatIndex: message.seatIndex,
      deviceId: message.deviceId,
      hand: message.hand.displayName,
      yaw: message.yaw,
      pitch: message.pitch,
      roll: message.roll,
      quaternion: quaternion,
      strike: acceptedStrike,
      intensity: effectiveIntensity,
      stageX: poseProjection.displayPoint.dx,
      stageY: poseProjection.displayPoint.dy,
      bellId: bellId,
      octave: effectiveOctave,
      timestampUs: message.timestampUs,
    );
    _hammerSensorDataByDeviceId[message.deviceId] = _latestSensorData!;

    if (!_ninjaMode && acceptedStrike) {
      _handleStrike(
        effectiveIntensity,
        bellId: bellId,
        region: strikeHit?.region ?? StageStrikeRegion.center,
      );
    }

    _requestStageRefresh(immediate: acceptedStrike || _ninjaMode);
  }

  /// 处理 WebSocket 消息
  void _handleMessage(WebSocketMessage message) {
    _messageCount++;

    switch (message.type) {
      case 'sensor':
        _handleSensorData(message.data);
        break;
      case 'heartbeat':
      case 'welcome':
      case 'pong':
        break;
      default:
        debugPrint('未知消息类型: ${message.type}');
    }

    _notifySafely();
  }

  void _handleSensorData(Map<String, dynamic> data) {
    try {
      _latestSensorData = SensorData.fromJson(data);
      final incomingOctave = _latestSensorData?.octave;
      if (incomingOctave != null) {
        _currentOctave = incomingOctave.clamp(
          AppConstants.minOctave,
          AppConstants.maxOctave,
        );
      }

      if (_latestSensorData!.strike) {
        final intensity = (_latestSensorData!.intensity * _sensitivity).clamp(
          0.0,
          1.0,
        );
        _handleStrike(intensity);
      }
    } catch (error) {
      debugPrint('解析传感器数据失败: $error');
    }
  }

  void _handleStrike(
    double intensity, {
    int? bellId,
    StageStrikeRegion region = StageStrikeRegion.center,
    int? transportMs,
  }) {
    if (isDemoPaused) return;
    _onAnyStrike();
    final baseBellId = bellId ?? _resolveBellIdForLatestSensor();
    final resolvedBellId = _resolveBellIdForRegion(baseBellId, region);
    _lastStrikeBellId = baseBellId;

    _checkFollowAlongHit(baseBellId);

    if (_audioEnabled) {
      unawaited(
        _audioService.playBell(resolvedBellId, intensity).then((strikeToAudioMs) {
          if (transportMs == null) return;
          var metrics = _latencyMetrics.recordStrike(
            transportMs: transportMs,
            strikeToAudioMs: strikeToAudioMs,
          );
          final rtt = _visionService.lastRttMs;
          if (rtt != null) {
            metrics = metrics.withWsRtt(rtt);
          }
          _latencyMetrics = metrics;
          _appendLatencySample(
            transportMs: transportMs,
            strikeToAudioMs: strikeToAudioMs,
            bellId: baseBellId,
            wsRttMs: rtt,
          );
          _notifySafely();
        }),
      );
    }

    _bellStates[baseBellId] = true;
    _bellReleaseTimers.remove(baseBellId)?.cancel();
    _bellReleaseTimers[baseBellId] = Timer(
      AppConstants.bellHighlightDuration,
      () {
        _bellReleaseTimers.remove(baseBellId);
        _bellStates[baseBellId] = false;
        _requestStageRefresh(immediate: true);
      },
    );

    debugPrint(
      '敲击编钟 base=$baseBellId play=$resolvedBellId region=$region，强度: ${intensity.toStringAsFixed(2)}',
    );
  }

  void _appendLatencySample({
    required int transportMs,
    required int strikeToAudioMs,
    required int bellId,
    int? wsRttMs,
  }) {
    _latencyHistory.add(
      LatencySample(
        recordedAt: DateTime.now(),
        transportMs: transportMs,
        strikeToAudioMs: strikeToAudioMs,
        totalMs: transportMs + strikeToAudioMs,
        wsRttMs: wsRttMs,
        bellId: bellId,
      ),
    );
    while (_latencyHistory.length > LatencyCsvExporter.maxHistory) {
      _latencyHistory.removeAt(0);
    }
  }

  bool _shouldAcceptUdpStrike(
    UdpHammerMessage message, {
    required double adjustedIntensity,
    required bool hasHitRegion,
  }) {
    if (!message.isStrike) {
      return false;
    }
    if (!hasHitRegion) {
      return false;
    }
    if (adjustedIntensity < AppConstants.minUiStrikeIntensity) {
      return false;
    }

    final eventTime = message.timestampUs == null
        ? DateTime.now()
        : DateTime.fromMicrosecondsSinceEpoch(message.timestampUs!);
    final lastAccepted = _lastAcceptedStrikeAtByDeviceId[message.deviceId];
    if (lastAccepted != null &&
        eventTime.difference(lastAccepted) < AppConstants.uiStrikeDebounce) {
      return false;
    }

    _lastAcceptedStrikeAtByDeviceId[message.deviceId] = eventTime;
    return true;
  }

  double? _resolveGestureStrikeIntensity({
    required _HammerGestureState state,
    required String deviceId,
    required DateTime timestamp,
    required Quaternion quaternion,
    required Offset strikePoint,
    required StageStrikeHitResult? strikeHit,
  }) {
    const double minDownwardVelocity = 0.22;
    const double minAngularVelocity = 105.0;
    const double forceAngularVelocity = 180.0;
    const double minLockDurationMs = 55.0;

    final previousQuaternion = state.previousQuaternion;
    final previousStrikePoint = state.previousStrikePoint;
    final previousTimestamp = state.previousTimestamp;
    final sameHit = _sameStageStrikeHit(state.lockedHit, strikeHit);

    if (!sameHit) {
      state.lockedHit = strikeHit;
      state.lockedAt = strikeHit == null ? null : timestamp;
    } else if (strikeHit != null) {
      state.lockedAt ??= timestamp;
    }

    double dtSec = 0.0;
    if (previousTimestamp != null) {
      dtSec = math
          .max(
            0.001,
            timestamp.difference(previousTimestamp).inMicroseconds / 1000000.0,
          )
          .toDouble();
    }

    double angularVelocity = 0.0;
    if (previousQuaternion != null && dtSec > 0.0) {
      angularVelocity = previousQuaternion.angleToDegrees(quaternion) / dtSec;
    }

    double downwardVelocity = 0.0;
    if (previousStrikePoint != null && dtSec > 0.0) {
      downwardVelocity = (strikePoint.dy - previousStrikePoint.dy) / dtSec;
    }

    state.previousQuaternion = quaternion;
    state.previousStrikePoint = strikePoint;
    state.previousTimestamp = timestamp;

    if (strikeHit == null) {
      state.lockedHit = null;
      state.lockedAt = null;
      return null;
    }

    final lockAgeMs = state.lockedAt == null
        ? 0.0
        : timestamp.difference(state.lockedAt!).inMilliseconds.toDouble();
    if (lockAgeMs < minLockDurationMs) {
      return null;
    }

    final lastAccepted = _lastAcceptedStrikeAtByDeviceId[deviceId];
    if (lastAccepted != null &&
        timestamp.difference(lastAccepted) < AppConstants.uiStrikeDebounce) {
      return null;
    }

    final directionalHit =
        downwardVelocity >= minDownwardVelocity &&
        angularVelocity >= minAngularVelocity;
    final forceHit = angularVelocity >= forceAngularVelocity;
    if (!directionalHit && !forceHit) {
      return null;
    }

    _lastAcceptedStrikeAtByDeviceId[deviceId] = timestamp;
    final normalized =
        ((angularVelocity - minAngularVelocity) / (360.0 - minAngularVelocity))
            .clamp(0.38, 1.0);
    debugPrint(
      'Gesture strike device=$deviceId bell=${strikeHit.bellId} region=${strikeHit.region} '
      'downV=${downwardVelocity.toStringAsFixed(3)} angV=${angularVelocity.toStringAsFixed(1)} '
      'lockAge=${lockAgeMs.toStringAsFixed(0)}ms',
    );
    return normalized.toDouble();
  }

  bool _sameStageStrikeHit(
    StageStrikeHitResult? left,
    StageStrikeHitResult? right,
  ) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.bellId == right.bellId && left.region == right.region;
  }

  int _resolveBellIdForLatestSensor() {
    final sensor = _latestSensorData;
    if (sensor == null) return BellMapping.getBellId(_currentOctave, 'C')!;
    if (sensor.bellId != null) return sensor.bellId!;
    if (sensor.yaw != null && sensor.pitch != null) {
      return _mapAnglesToBellId(sensor.yaw!, sensor.pitch!);
    }
    return _mapQuaternionToBell(sensor.quaternion);
  }

  int _mapAnglesToBellId(double yaw, double pitch) {
    final isUpperLayer = pitch > AppConstants.upperLayerPitchThreshold;
    final notes = isUpperLayer
        ? AppConstants.upperLayerNotes
        : AppConstants.lowerLayerNotes;

    final range = AppConstants.yawMax - AppConstants.yawMin;
    final normalized = ((yaw - AppConstants.yawMin) / range).clamp(0.0, 1.0);
    final scaledIndex = normalized * notes.length;
    final noteIndex = math.min(notes.length - 1, scaledIndex.floor());
    final note = notes[noteIndex];
    return BellMapping.getBellId(_currentOctave, note)!;
  }

  int _mapQuaternionToBell(Quaternion q) {
    final pitch = 2 * (q.w * q.y - q.z * q.x);
    final roll = 2 * (q.w * q.x + q.y * q.z);
    final octave = ((pitch.abs() * 5).toInt() % 5) + 1;
    final noteIndex = (roll.abs() * 12).toInt() % 12;
    return ((octave - 1) * 12 + noteIndex + 1).clamp(1, AppConstants.bellCount);
  }

  void onBellTapped(
    int bellId,
    double intensity, {
    StageStrikeRegion region = StageStrikeRegion.center,
  }) {
    if (!allowTouchInput) return;
    _onAnyStrike();
    _checkFollowAlongHit(bellId);
    final resolvedBellId = _resolveBellIdForRegion(bellId, region);
    if (_audioEnabled) {
      _audioService.playBell(resolvedBellId, intensity);
    }

    if (_wsStatus == ConnectionStatus.connected) {
      _wsService.sendTouchEvent(resolvedBellId, intensity);
    }

    _bellStates[bellId] = true;
    _lastStrikeBellId = bellId;
    _bellReleaseTimers.remove(bellId)?.cancel();
    _bellReleaseTimers[bellId] = Timer(AppConstants.bellHighlightDuration, () {
      _bellReleaseTimers.remove(bellId);
      _bellStates[bellId] = false;
      _requestStageRefresh(immediate: true);
    });

    _requestStageRefresh(immediate: true);
  }

  int _resolveBellIdForRegion(int baseBellId, StageStrikeRegion region) {
    switch (region) {
      case StageStrikeRegion.center:
        return baseBellId;
      case StageStrikeRegion.left:
      case StageStrikeRegion.right:
        return BellMapping.nextTwoScaleStepsBellId(baseBellId);
    }
  }

  bool getBellState(int bellId) {
    return _bellStates[bellId] ?? false;
  }

  void setCurrentOctave(int octave) {
    final safeOctave = octave.clamp(
      AppConstants.minOctave,
      AppConstants.maxOctave,
    );
    if (_currentOctave == safeOctave) return;
    _currentOctave = safeOctave;
    _requestStageRefresh(immediate: true);
    _notifySafely();
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _audioService.setVolume(_volume);
    _notifySafely();
  }

  void setSensitivity(double sensitivity) {
    _sensitivity = sensitivity.clamp(0.0, 1.0);
    _notifySafely();
  }

  List<BellAssetAuditEntry> auditBellAssets() => BellMapping.auditAllBells();

  void setBellAssetOverride(int bellId, String assetFileName) {
    _audioService.setBellAssetOverride(bellId, assetFileName);
    _notifySafely();
  }

  void clearBellAssetOverrides() {
    _audioService.clearAllBellAssetOverrides();
    _notifySafely();
  }

  void setAudioEnabled(bool enabled) {
    _audioEnabled = enabled;
    _audioService.setEnabled(enabled);
    _notifySafely();
  }

  void sendTestMessage() {
    if (_wsStatus != ConnectionStatus.connected) return;
    _wsService.sendMessage(
      WebSocketMessage(type: 'test', data: {'message': 'Flutter测试消息'}),
    );
  }

  void _refreshConnectionState() {
    if (_inputMode == InputMode.vision) {
      if (_visionStatus == ConnectionStatus.connected && !_visionService.isSignalLost) {
        _connectionStatus = ConnectionStatus.connected;
        return;
      }
      if (_visionStatus == ConnectionStatus.reconnecting ||
          (_visionStatus == ConnectionStatus.connected &&
              _visionService.isSignalLost)) {
        _connectionStatus = ConnectionStatus.reconnecting;
        if (_visionService.isSignalLost) {
          _errorMessage = '追踪信号丢失';
        }
        return;
      }
      if (_visionStatus == ConnectionStatus.connecting) {
        _connectionStatus = ConnectionStatus.connecting;
        return;
      }
      if (_visionStatus == ConnectionStatus.error) {
        _connectionStatus = ConnectionStatus.error;
        return;
      }
      _connectionStatus = ConnectionStatus.disconnected;
      return;
    }

    if (_activeHammers.isNotEmpty || _wsStatus == ConnectionStatus.connected) {
      _connectionStatus = ConnectionStatus.connected;
      return;
    }

    if (_wsStatus == ConnectionStatus.reconnecting) {
      _connectionStatus = ConnectionStatus.reconnecting;
      return;
    }

    if (_wsStatus == ConnectionStatus.connecting) {
      _connectionStatus = ConnectionStatus.connecting;
      return;
    }

    if (_udpListening) {
      _connectionStatus = ConnectionStatus.listening;
      return;
    }

    if (_errorMessage.isNotEmpty || _wsStatus == ConnectionStatus.error) {
      _connectionStatus = ConnectionStatus.error;
      return;
    }

    _connectionStatus = ConnectionStatus.disconnected;
  }

  String _buildConnectionSummary() {
    if (_inputMode == InputMode.vision) {
      if (_visionStatus == ConnectionStatus.connected) {
        if (_visionService.isSignalLost) {
          return '视觉追踪 · 追踪信号丢失';
        }
        final sticks = _stickFramesById.values
            .where((f) => f.isVisible)
            .map((f) => '棒${f.stickId}')
            .join('、');
        return '视觉追踪 · $_visionWsUrl${sticks.isNotEmpty ? ' · $sticks' : ''}';
      }
      if (_visionStatus == ConnectionStatus.reconnecting) {
        return '视觉追踪 · 重新连接中...';
      }
      return '视觉追踪 · 未连接';
    }

    if (_inputMode == InputMode.touchOnly) {
      return '仅触控模式';
    }

    if (_activeHammers.isNotEmpty) {
      return 'UDP ${AppConstants.defaultUdpPort} · 活跃击锤: ${_buildActiveHammerSummary()}';
    }

    if (_isBleProvisioning) {
      return '蓝牙配网中 · 目标 WiFi: $_provisioningTargetSsid';
    }

    if (_udpListening) {
      return 'UDP ${AppConstants.defaultUdpPort} · 等待硬件广播';
    }

    if (_wsStatus == ConnectionStatus.connected) {
      return 'WebSocket · $_wsUrl';
    }

    return '未连接到数字编钟硬件';
  }

  String _buildActiveHammerSummary() {
    if (_activeHammers.isEmpty) {
      return '无';
    }
    return _activeHammers
        .map((hammer) => '${hammer.displayLabel}(ID ${hammer.hammerId})')
        .join('，');
  }

  void _requestStageRefresh({bool immediate = false}) {
    if (_isDisposed) return;
    _bumpStageRevision(DateTime.now());
  }

  void _bumpStageRevision(DateTime timestamp) {
    if (_isDisposed) return;
    _lastStageRefreshAt = timestamp;
    _stageRevision.value++;
  }

  void _notifySafely() {
    if (_isDisposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    for (final timer in _bellReleaseTimers.values) {
      timer.cancel();
    }
    _bellReleaseTimers.clear();
    _stageRefreshTimer?.cancel();
    _stageRefreshTimer = null;
    _followTimer?.cancel();
    _followTimer = null;
    _demoModeTimer?.cancel();
    _demoModeTimer = null;
    _udpService.dispose();
    _wsService.dispose();
    _visionService.dispose();
    _audioService.dispose();
    _stageRevision.dispose();
    super.dispose();
  }
}

class _HammerGestureState {
  Quaternion? previousQuaternion;
  Offset? previousStrikePoint;
  DateTime? previousTimestamp;
  StageStrikeHitResult? lockedHit;
  DateTime? lockedAt;
}
