import 'dart:async';
import 'dart:developer' as developer;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/sensor_data.dart';
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
  Timer? _stickStaleTimer;

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
    final frame = VisionStickFrame.tryParse(data.toString());
    if (frame == null) return;

    _lastFrameAt = DateTime.now();
    _lastReceivedAtByStickId[frame.stickId] = _lastFrameAt!;
    _lastFrames[frame.stickId] = frame;
    _frameController?.add(frame);
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
      if (!isStale || current?.isVisible == false) {
        continue;
      }
      final lost = VisionStickFrame.lost(stickId: stickId);
      _lastFrames[stickId] = lost;
      _frameController?.add(lost);
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

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopFrameTimeoutWatch();
    _stopStickStaleWatch();
    try {
      await _channel?.sink.close(1000);
      _channel = null;
    } catch (_) {}
    _lastFrames.clear();
    _lastReceivedAtByStickId.clear();
    _updateStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _frameController?.close();
    _statusController?.close();
    _frameController = null;
    _statusController = null;
  }
}
