import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/sensor_data.dart';
import '../models/vision_tracker_status.dart';
import '../models/vision_stick_frame.dart';
import '../utils/constants.dart';

/// 视觉追踪 WebSocket 服务（接收 Python/OpenCV 坐标推送）
class VisionTrackingService {
  WebSocketChannel? _channel;
  StreamController<VisionStickFrame>? _frameController;
  StreamController<ConnectionStatus>? _statusController;
  Timer? _reconnectTimer;
  Timer? _frameTimeoutTimer;
  String _wsUrl = AppConstants.defaultVisionWsUrl;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _shouldReconnect = true;
  DateTime? _lastFrameAt;
  final Map<int, VisionStickFrame> _lastFrames = {};
  final Map<int, DateTime> _lastReceivedAtByStickId = {};
  final Map<int, DateTime> _staleSinceByStickId = {};
  Timer? _stickStaleTimer;
  Timer? _pingTimer;
  DateTime? _lastPingSentAt;
  int? _lastRttMs;
  VisionTrackerStatus? _trackerStatus;
  final StreamController<int> _rttController = StreamController<int>.broadcast();
  final StreamController<VisionTrackerStatus> _trackerStatusController =
      StreamController<VisionTrackerStatus>.broadcast();

  Stream<int> get rttStream => _rttController.stream;
  Stream<VisionTrackerStatus> get trackerStatusStream =>
      _trackerStatusController.stream;
  int? get lastRttMs => _lastRttMs;
  VisionTrackerStatus? get trackerStatus => _trackerStatus;

  Stream<VisionStickFrame> get frameStream =>
      _frameController?.stream ?? const Stream.empty();

  Stream<ConnectionStatus> get statusStream =>
      _statusController?.stream ?? const Stream.empty();

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  DateTime? get lastFrameAt => _lastFrameAt;
  Map<int, VisionStickFrame> get lastFrames => Map.unmodifiable(_lastFrames);
  String get wsUrl => _wsUrl;

  bool get isSignalLost {
    if (!isConnected) return _status == ConnectionStatus.reconnecting;
    if (_lastFrameAt == null) return true;
    return DateTime.now().difference(_lastFrameAt!) >
        AppConstants.visionFrameTimeout;
  }

  VisionTrackingService() {
    _frameController = StreamController<VisionStickFrame>.broadcast();
    _statusController = StreamController<ConnectionStatus>.broadcast();
  }

  Future<void> connect(String wsUrl) async {
    _wsUrl = wsUrl;
    _shouldReconnect = true;
    await _connect();
  }

  Future<void> _connect() async {
    if (_status == ConnectionStatus.connecting) {
      return;
    }

    try {
      _updateStatus(ConnectionStatus.connecting);
      developer.log('视觉追踪连接 $_wsUrl', name: 'VisionTrackingService');

      await _channel?.sink.close(1000);
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await _channel!.ready;

      _updateStatus(ConnectionStatus.connected);
      _lastFrameAt = DateTime.now();
      _startFrameTimeoutWatch();
      _startStickStaleWatch();
      _startPingLoop();

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      developer.log('视觉追踪连接失败: $e', name: 'VisionTrackingService', error: e);
      _updateStatus(ConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      final parsed = jsonDecode(data.toString());
      if (parsed is Map<String, dynamic>) {
        final type = parsed['type'] as String?;
        if (type == 'pong' && _lastPingSentAt != null) {
          _lastRttMs =
              DateTime.now().difference(_lastPingSentAt!).inMilliseconds;
          _rttController.add(_lastRttMs!);
          return;
        }
        if (type == 'tracker_status') {
          _trackerStatus = VisionTrackerStatus.fromJson(parsed);
          _trackerStatusController.add(_trackerStatus!);
          return;
        }
        if (type == 'calibration_started' || type == 'calibration_complete') {
          _trackerStatus = VisionTrackerStatus(
            threshold: (parsed['threshold'] as num?)?.toInt() ??
                _trackerStatus?.threshold ??
                220,
            calibrating: type == 'calibration_started',
            calibrationProgress: type == 'calibration_complete' ? 1.0 : 0.0,
            updatedAt: DateTime.now(),
          );
          _trackerStatusController.add(_trackerStatus!);
          return;
        }
      }
    } catch (_) {}

    final frame = VisionStickFrame.tryParse(data.toString());
    if (frame == null) return;

    _lastFrameAt = DateTime.now();
    _lastReceivedAtByStickId[frame.stickId] = _lastFrameAt!;
    _staleSinceByStickId.remove(frame.stickId);
    _lastFrames[frame.stickId] = frame;
    _frameController?.add(frame);
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(AppConstants.heartbeatInterval, (_) {
      sendPing();
    });
  }

  void _stopPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _startStickStaleWatch() {
    _stickStaleTimer?.cancel();
    _stickStaleTimer = Timer.periodic(
      AppConstants.visionStickStaleTimeout ~/ 2,
      (_) => _emitStaleStickStates(),
    );
  }

  void _stopStickStaleWatch() {
    _stickStaleTimer?.cancel();
    _stickStaleTimer = null;
  }

  void _emitStaleStickStates() {
    if (!isConnected) return;
    final now = DateTime.now();
    for (final stickId in [1, 2]) {
      final receivedAt = _lastReceivedAtByStickId[stickId];
      final current = _lastFrames[stickId];
      final isStale = receivedAt == null ||
          now.difference(receivedAt) > AppConstants.visionStickStaleTimeout;

      if (!isStale) {
        _staleSinceByStickId.remove(stickId);
        continue;
      }

      _staleSinceByStickId.putIfAbsent(stickId, () => now);
      final staleAge = now.difference(_staleSinceByStickId[stickId]!);

      if (current != null &&
          current.isVisible &&
          staleAge < AppConstants.visionPredictionHold) {
        final decay = 1.0 - staleAge.inMilliseconds /
            AppConstants.visionPredictionHold.inMilliseconds;
        _frameController?.add(
          current.copyWith(confidence: current.confidence * decay),
        );
        continue;
      }

      if (current?.isVisible != false) {
        final lost = VisionStickFrame.lost(stickId: stickId);
        _lastFrames[stickId] = lost;
        _frameController?.add(lost);
      }
    }
  }

  void _onError(Object error) {
    developer.log('视觉追踪错误: $error', name: 'VisionTrackingService', error: error);
    _updateStatus(ConnectionStatus.error);
    _scheduleReconnect();
  }

  void _onDone() {
    developer.log('视觉追踪连接关闭', name: 'VisionTrackingService');
    _updateStatus(ConnectionStatus.disconnected);
    _stopFrameTimeoutWatch();
    _stopStickStaleWatch();
    _stopPingLoop();
    _scheduleReconnect();
  }

  void _startFrameTimeoutWatch() {
    _frameTimeoutTimer?.cancel();
    _frameTimeoutTimer = Timer.periodic(
      AppConstants.visionFrameTimeout ~/ 2,
      (_) {
        if (isConnected && isSignalLost) {
          developer.log('追踪信号丢失', name: 'VisionTrackingService');
        }
      },
    );
  }

  void _stopFrameTimeoutWatch() {
    _frameTimeoutTimer?.cancel();
    _frameTimeoutTimer = null;
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();
    _updateStatus(ConnectionStatus.reconnecting);
    _reconnectTimer = Timer(AppConstants.visionReconnectDelay, () {
      _connect();
    });
  }

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController?.add(newStatus);
    }
  }

  void sendStrikeAck({
    required int bellId,
    required int stickId,
  }) {
    if (!isConnected) return;
    try {
      final msg =
          '{"type":"strike_ack","bellId":$bellId,"stick_id":$stickId,"timestamp":${DateTime.now().millisecondsSinceEpoch}}';
      _channel?.sink.add(msg);
    } catch (_) {}
  }

  void requestThresholdRecalibration() {
    if (!isConnected) return;
    try {
      _channel?.sink.add('{"type":"recalibrate_threshold"}');
    } catch (_) {}
  }

  void setThreshold(int threshold) {
    if (!isConnected) return;
    final safe = threshold.clamp(160, 245);
    try {
      _channel?.sink.add('{"type":"set_threshold","threshold":$safe}');
    } catch (_) {}
  }

  void sendPing() {
    if (!isConnected) return;
    try {
      _lastPingSentAt = DateTime.now();
      _channel?.sink.add(
        '{"type":"ping","timestamp":${_lastPingSentAt!.millisecondsSinceEpoch}}',
      );
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopFrameTimeoutWatch();
    _stopStickStaleWatch();
    _stopPingLoop();
    try {
      await _channel?.sink.close(1000);
      _channel = null;
    } catch (_) {}
    _lastFrames.clear();
    _lastReceivedAtByStickId.clear();
    _trackerStatus = null;
    _updateStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _frameController?.close();
    _statusController?.close();
    _rttController.close();
    _trackerStatusController.close();
    _frameController = null;
    _statusController = null;
  }
}
