import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../models/sensor_data.dart';
import '../models/song_model.dart';
import '../models/song_library.dart';
import '../services/audio_service.dart';
import '../services/ble_provisioning_service.dart';
import '../services/mock_hammer_source.dart';
import '../services/strike_router.dart';
import '../services/udp_hammer_service.dart';
import '../services/wifi_info_service.dart';
import '../services/websocket_service.dart';
import '../utils/constants.dart';
import '../utils/hammer_pose_mapper.dart';
import '../utils/stage_hit_mapper.dart';
import '../utils/blade_trail.dart';
import '../utils/slash_detector.dart';

/// 应用状态管理
class AppProvider with ChangeNotifier {
  final WebSocketService _wsService = WebSocketService();
  final UdpHammerService _udpService = UdpHammerService();
  final AudioService _audioService = AudioService();
  BleProvisioningService? _bleProvisioningService;
  final WifiInfoService _wifiInfoService = WifiInfoService();
  final HammerPoseMapper _hammerPoseMapper = HammerPoseMapper();
  final ValueNotifier<int> _stageRevision = ValueNotifier<int>(0);
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  MockHammerSource? _mockSource;
  bool _mockEnabled = false;
  String _mockScenario = 'idle';

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  ConnectionStatus _wsStatus = ConnectionStatus.disconnected;
  String _wsUrl = AppConstants.defaultWsUrl;
  String _errorMessage = '';
  bool _udpListening = false;
  DateTime? _listeningStartedAt;
  int? _lastHammerOctave; // 锤子上次上报的八度，只有变化时才更新
  List<ActiveHammerInfo> _activeHammers = [];
  final Map<String, SensorData> _hammerSensorDataByDeviceId = {};
  final Map<String, DateTime> _lastAcceptedStrikeAtByDeviceId = {};
  final Map<String, int> _lastHoveredBellId = {};
  final Map<String, int> _pendingNinjaSnapBell = {};
  final Map<String, StageStrikeRegion> _pendingNinjaSnapRegion = {};
  final Map<String, DateTime> _ninjaSnapBellCooldown = {}; // 每个钟的冷却时间
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
  bool _isDisposed = false;
  DateTime? _lastStageRefreshAt;
  Timer? _stageRefreshTimer;

  // 自动重试 watchdog：监听期间定时检查，2s 内零消息就重 bind。
  Timer? _udpWatchdogTimer;
  DateTime _lastUdpMessageAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _consecutiveEmptyScans = 0;

  bool _ninjaMode = false;
  final Map<String, BladeTrail> _bladeTrailsByDeviceId = {};
  final Map<String, SlashState> _slashStatesByDeviceId = {};

  Song? _currentSong;
  FollowAlongProgress _followProgress = const FollowAlongProgress();
  Timer? _followTimer;
  int _followElapsedMs = 0;
  final Set<int> _followHitNoteIndices = {};
  int _countdownRemaining = 0;

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
    }
    _notifySafely();
  }

  Map<String, BladeTrail> get bladeTrails => _bladeTrailsByDeviceId;

  bool get mockEnabled => _mockEnabled;
  String get mockScenario => _mockScenario;

  void toggleMock({String? scenario}) {
    if (scenario != null) _mockScenario = scenario;
    _mockEnabled = !_mockEnabled;
    if (_mockEnabled) {
      _mockSource ??= MockHammerSource(
        service: _udpService,
        scenario: _mockScenario,
      );
      _mockSource!.setScenario(_mockScenario);
      _mockSource!.start();
      _errorMessage = 'Mock 数据源已启用 (场景: $_mockScenario)';
    } else {
      _mockSource?.stop();
      _errorMessage = 'Mock 数据源已关闭';
    }
    _notifySafely();
  }

  /// 如果编译时通过 --dart-define=MOCK=<scenario> 指定了 mock 场景，
  /// 则在启动时自动打开 Mock 数据源（无需硬件）。
  void initMockIfRequested(String scenario) {
    if (scenario.isEmpty) return;
    _mockScenario = scenario;
    _mockEnabled = true;
    _mockSource ??= MockHammerSource(
      service: _udpService,
      scenario: _mockScenario,
    );
    _mockSource!.setScenario(_mockScenario);
    _mockSource!.start();
    // 不触发 notifyListeners() — Provider 初始化期间，UI 尚未 build。
  }

  Song? get currentSong => _currentSong;
  FollowAlongProgress get followProgress => _followProgress;
  bool get isFollowAlongActive =>
      _followProgress.state == FollowAlongState.playing ||
      _followProgress.state == FollowAlongState.countdown;
  int get countdownRemaining => _countdownRemaining;
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
    startHardwareDiscovery();
    // 启动时自动加载当前 WiFi 信息，供配网界面使用
    loadCurrentWifiSsid();
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
        // 两个锤子 BNO085 安装方向相同，统一使用默认配置
        // 如需单独调整某个锤子：setDeviceConfig(deviceId, HammerDeviceConfig(signX: ..., signY: ...))
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
  }

  /// 启动 UDP 硬件监听
  Future<void> startHardwareDiscovery() async {
    if (_udpListening) return;

    _connectionStatus = ConnectionStatus.listening;
    _notifySafely();

    try {
      await _udpService.start();
      _udpListening = true;
      _listeningStartedAt = DateTime.now();
      _currentOctave = AppConstants.defaultOctave;
      _lastUdpMessageAt = DateTime.now();
      _consecutiveEmptyScans = 0;
      _startUdpWatchdog();
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

  /// 周期检查：若过去 [_udpEmptyThreshold] 内没有收到任何消息，
  /// 且当前没有活跃击锤，触发一次 UDP 重 bind（应对路由器断电等外部场景）。
  void _startUdpWatchdog() {
    _udpWatchdogTimer?.cancel();
    _udpWatchdogTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkUdpHealth(),
    );
  }

  static const Duration _udpEmptyThreshold = Duration(seconds: 2);

  Future<void> _checkUdpHealth() async {
    if (!_udpListening || _mockEnabled) return;
    final now = DateTime.now();
    final idleFor = now.difference(_lastUdpMessageAt);

    // 1. 当前已经有活跃击锤 → 健康
    if (_activeHammers.isNotEmpty) {
      _consecutiveEmptyScans = 0;
      return;
    }

    // 2. 启动后 5 秒宽限期内：什么都不做（等待首次固件广播到达）
    if (idleFor < _udpEmptyThreshold) return;

    _consecutiveEmptyScans++;
    // 3. 累计两次空扫（≥10s 无数据） → 触发一次重 bind
    if (_consecutiveEmptyScans >= 2) {
      _consecutiveEmptyScans = 0;
      _errorMessage = '长时间无 UDP 数据，正在重新监听；'
          '如仍为空请检查路由器与防火墙';
      await restartHardwareDiscovery();
    }
  }

  Future<void> restartHardwareDiscovery() async {
    try {
      await _udpService.restart();
      _udpListening = true;
      _listeningStartedAt = DateTime.now();
      _currentOctave = AppConstants.defaultOctave;
      _errorMessage = '';
    } catch (error) {
      _udpListening = false;
      _errorMessage = 'UDP 监听失败: $error';
    }
    _refreshConnectionState();
    _notifySafely();
  }

  /// 重置所有击锤的相对姿态基准，使挥动回到原点。
  void recenterAllHammers() {
    _hammerPoseMapper.recenterAll();
    for (final hammer in List.of(_activeHammers)) {
      _hammerPoseMapper.recenterDevice(hammer.deviceId);
    }
    _errorMessage = '所有击锤姿态已重置';
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
        // 桌面端提示用户使用 SoftAP 网页配网兜底
        if (!Platform.isAndroid && !Platform.isIOS) {
          _bleProvisioningMessage = '桌面端暂不支持蓝牙扫描，'
              '请用手机 App 扫码配网'
              '或连接击锤热点 BianzongHammer-XXXXXX（密码 12345678）'
              '后打开 http://192.168.4.1 完成配网';
        } else {
          _bleProvisioningMessage = '未发现可配网击锤，请确认设备已上电并靠近手机';
        }
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
    _messageCount++;
    _lastUdpMessageAt = DateTime.now();
    _consecutiveEmptyScans = 0;
    final incomingOctave = message.octave?.clamp(
      AppConstants.minOctave,
      AppConstants.maxOctave,
    );
    final effectiveOctave = _currentOctave;
    // 记录锤子八度历史，只有两次不同才认为是真实按键（过滤 GPIO 悬空误读）
    if (incomingOctave != null && !isFollowAlongActive) {
      if (_lastHammerOctave != null &&
          incomingOctave != _lastHammerOctave) {
        _currentOctave = incomingOctave;
      }
      _lastHammerOctave = incomingOctave;
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
      linearAccelX: message.linearAccelX,
      linearAccelY: message.linearAccelY,
      linearAccelZ: message.linearAccelZ,
    );

    final strikePoint = poseProjection.strikePoint;
    final strikeHit = StageHitMapper.hitTestStagePoint(
      currentOctave: effectiveOctave,
      point: strikePoint,
    );
    final bellId = strikeHit?.bellId;
    // 记住光标最后悬浮的钟（敲击时兜底用）
    if (strikeHit != null) {
      _lastHoveredBellId[message.deviceId] = strikeHit.bellId;
    }
    final hoveredBell = _lastHoveredBellId[message.deviceId];

    // ── 忍者模式磁吸吸附 ──────────────────────
    Offset snappedPoint = strikePoint;
    StageStrikeRegion? snapRegion;
    if (_ninjaMode) {
      const double snapRadius = 0.11;
      const double snapStrength = 0.50;
      const double autoStrikeDist = 0.08;
      double bestRegionDist = double.infinity;
      Offset bestRegionCenter = strikePoint;
      int bestBellId = 1;
      StageStrikeRegion bestRegion = StageStrikeRegion.center;

      for (final bell in StageHitMapper.bellLayouts) {
          final bid = BellMapping.getBellId(effectiveOctave, bell.note);
          if (bid == null) continue;
          final center = Offset(bell.x, bell.y);

          // 根据光标相对位置选择吸附目标区域
          final dx = strikePoint.dx - center.dx;
          final dy = strikePoint.dy - center.dy;
          StageStrikeRegion region;
          Offset target;
          if (dx < -0.02) {
            // 光标在左边 → 吸到左侧
            region = StageStrikeRegion.left;
            target = Offset(center.dx - 0.035, center.dy + 0.04);
          } else if (dx > 0.02) {
            // 光标在右边 → 吸到右侧
            region = StageStrikeRegion.right;
            target = Offset(center.dx + 0.035, center.dy + 0.04);
          } else {
            // 光标在中间 → 吸到正面
            region = StageStrikeRegion.center;
            target = Offset(center.dx, center.dy + 0.06);
          }

          final dist = (strikePoint - target).distance;
          if (dist < bestRegionDist) {
            bestRegionDist = dist;
            bestRegionCenter = target;
            bestBellId = bid;
            bestRegion = region;
          }
        }

      if (bestRegionDist < snapRadius) {
        snappedPoint = Offset(
          strikePoint.dx + (bestRegionCenter.dx - strikePoint.dx) * snapStrength,
          strikePoint.dy + (bestRegionCenter.dy - strikePoint.dy) * snapStrength,
        );
        _lastHoveredBellId[message.deviceId] = bestBellId;
        snapRegion = bestRegion;
        // 自动斩击：用吸附后的距离，按钟冷却
        final snappedDist = (snappedPoint - bestRegionCenter).distance;
        final snapNow = DateTime.now();
        final bellCooldown = _ninjaSnapBellCooldown[message.deviceId];
        final bellCooldownOk =
            bellCooldown == null || snapNow.isAfter(bellCooldown);
        if (snappedDist < autoStrikeDist && bellCooldownOk) {
          _pendingNinjaSnapBell[message.deviceId] = bestBellId;
          _pendingNinjaSnapRegion[message.deviceId] = snapRegion!;
          _ninjaSnapBellCooldown[message.deviceId] =
              snapNow.add(const Duration(milliseconds: 500));
        }
      }
    }

    final adjustedIntensity = (message.force * _sensitivity).clamp(0.0, 1.0);
    final gestureState = _gestureStateByDeviceId.putIfAbsent(
      message.deviceId,
      _HammerGestureState.new,
    );

    // 维护忍者模式轨迹与 slash 状态机（保持原行为）
    final trail = _bladeTrailsByDeviceId.putIfAbsent(
      message.deviceId,
      BladeTrail.new,
    );
    final slashState = _slashStatesByDeviceId.putIfAbsent(
      message.deviceId,
      SlashState.new,
    );

    // 用 StrikeRouter 收集所有"应在此帧触发"的击打决策；
    // 这样做替代了原本散落在 UDP 接受判定 / gesture 补判 / 忍者斩击 三处的 if/else。
    // 敲击时用最后悬浮的钟兜底
    final effectiveStrikeHit = strikeHit ??
        (hoveredBell != null
            ? StageStrikeHitResult(
                bellId: hoveredBell, region: StageStrikeRegion.center)
            : null);

    final decisions = StrikeRouter.route(
      message: message,
      env: StrikeRouterEnv(
        currentOctave: effectiveOctave,
        strikePoint: snappedPoint,
        strikeHit: effectiveStrikeHit,
        ninjaMode: _ninjaMode,
        sensitivity: _sensitivity,
        previousStagePoint: _hammerSensorDataByDeviceId[message.deviceId]
                ?.stageX ??
            null,
        angularVelocity: poseProjection.angularVelocity,
        lastAcceptedStrikeAt:
            _lastAcceptedStrikeAtByDeviceId[message.deviceId],
        timestamp: timestamp,
        trail: trail,
        slashState: slashState,
        lastAcceptedStrikeAtRef:
            _lastAcceptedStrikeAtByDeviceId[message.deviceId],
      ),
    );

    // gesture 补判
    final gestureStrikeIntensity = _resolveGestureStrikeIntensity(
      state: gestureState,
      deviceId: message.deviceId,
      timestamp: timestamp,
      quaternion: quaternion,
      strikePoint: snappedPoint,
      strikeHit: effectiveStrikeHit,
    );

    final hardwareStrikeAccepted = decisions
        .any((d) => d.source == StrikeSource.firmwareStrike);
    final acceptedStrike = hardwareStrikeAccepted ||
        (gestureStrikeIntensity != null && strikeHit != null);

    if (gestureStrikeIntensity != null && strikeHit != null) {
      decisions.add(StrikeDecision(
        bellId: strikeHit.bellId,
        region: strikeHit.region,
        intensity: gestureStrikeIntensity,
        source: StrikeSource.gestureStrike,
      ));
    }

    final effectiveIntensity = () {
      final firmwareIntensity = decisions
          .where((d) => d.source == StrikeSource.firmwareStrike)
          .map((d) => d.intensity)
          .fold<double>(0.0, (a, b) => a > b ? a : b);
      return firmwareIntensity > 0 ? firmwareIntensity : adjustedIntensity;
    }();

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
      stageX: snappedPoint.dx,
      stageY: snappedPoint.dy,
      bellId: bellId,
      octave: effectiveOctave,
      timestampUs: message.timestampUs,
    );
    _hammerSensorDataByDeviceId[message.deviceId] = _latestSensorData!;

    // 忍者模式吸附自动斩击
    final pendingSnap = _pendingNinjaSnapBell.remove(message.deviceId);
    final pendingRegion = _pendingNinjaSnapRegion.remove(message.deviceId);
    if (pendingSnap != null) {
      decisions.add(StrikeDecision(
        bellId: pendingSnap,
        region: pendingRegion ?? StageStrikeRegion.center,
        intensity: 0.5,
        source: StrikeSource.ninjaSlash,
      ));
    }

    // 把决策列表兑现为实际播放
    for (final decision in decisions) {
      if (decision.source == StrikeSource.firmwareStrike ||
          decision.source == StrikeSource.gestureStrike ||
          decision.source == StrikeSource.ninjaSlash ||
          decision.source == StrikeSource.ninjaSlashTrail) {
        _handleStrike(
          decision.intensity,
          bellId: decision.bellId,
          region: decision.region,
        );
        _lastAcceptedStrikeAtByDeviceId[message.deviceId] = timestamp;
      }
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
  }) {
    final baseBellId = bellId ?? _resolveBellIdForLatestSensor();
    final resolvedBellId = _resolveBellIdForRegion(baseBellId, region);
    _lastStrikeBellId = baseBellId;

    _checkFollowAlongHit(baseBellId);

    if (_audioEnabled) {
      _audioService.playBell(resolvedBellId, intensity);
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

  double? _resolveGestureStrikeIntensity({
    required _HammerGestureState state,
    required String deviceId,
    required DateTime timestamp,
    required Quaternion quaternion,
    required Offset strikePoint,
    required StageStrikeHitResult? strikeHit,
  }) {
    const double minDownwardVelocity = 0.30;
    const double minAngularVelocity = 200.0;
    const double forceAngularVelocity = 350.0;
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
    _mockSource?.stop();
    _mockSource = null;
    _udpWatchdogTimer?.cancel();
    _udpWatchdogTimer = null;
    _udpService.dispose();
    _wsService.dispose();
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
