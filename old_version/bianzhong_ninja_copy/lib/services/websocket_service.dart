import 'dart:async';
import 'dart:developer' as developer;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/sensor_data.dart';
import '../utils/constants.dart';

/// WebSocket服务
class WebSocketService {
  WebSocketChannel? _channel;
  StreamController<WebSocketMessage>? _messageController;
  StreamController<ConnectionStatus>? _statusController;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  String _wsUrl = AppConstants.defaultWsUrl;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _shouldReconnect = true;

  Stream<WebSocketMessage> get messageStream =>
      _messageController?.stream ?? const Stream.empty();

  Stream<ConnectionStatus> get statusStream =>
      _statusController?.stream ?? const Stream.empty();

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;

  WebSocketService() {
    _messageController = StreamController<WebSocketMessage>.broadcast();
    _statusController = StreamController<ConnectionStatus>.broadcast();
  }

  /// 连接到WebSocket服务器
  Future<void> connect(String wsUrl) async {
    _wsUrl = wsUrl;
    _shouldReconnect = true;
    await _connect();
  }

  Future<void> _connect() async {
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected) {
      return;
    }

    try {
      _updateStatus(ConnectionStatus.connecting);
      developer.log('正在连接到 $_wsUrl', name: 'WebSocketService');

      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      // 等待连接建立
      await _channel!.ready;

      _updateStatus(ConnectionStatus.connected);
      developer.log('WebSocket已连接', name: 'WebSocketService');

      // 开始监听消息
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // 启动心跳
      _startHeartbeat();
    } catch (e) {
      developer.log('连接失败: $e', name: 'WebSocketService', error: e);
      _updateStatus(ConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  /// 处理接收到的消息
  void _onMessage(dynamic data) {
    try {
      final message = WebSocketMessage.fromJson(data.toString());
      developer.log('收到消息: ${message.type}', name: 'WebSocketService');
      _messageController?.add(message);
    } catch (e) {
      developer.log('消息解析失败: $e', name: 'WebSocketService', error: e);
    }
  }

  /// 处理错误
  void _onError(Object error) {
    developer.log(
      'WebSocket错误: $error',
      name: 'WebSocketService',
      error: error,
    );
    _updateStatus(ConnectionStatus.error);
    _scheduleReconnect();
  }

  /// 处理连接关闭
  void _onDone() {
    developer.log('WebSocket连接已关闭', name: 'WebSocketService');
    _updateStatus(ConnectionStatus.disconnected);
    _stopHeartbeat();
    _scheduleReconnect();
  }

  /// 发送消息
  void sendMessage(WebSocketMessage message) {
    if (!isConnected) {
      developer.log('未连接，无法发送消息', name: 'WebSocketService');
      return;
    }

    try {
      _channel?.sink.add(message.toJson());
      developer.log('发送消息: ${message.type}', name: 'WebSocketService');
    } catch (e) {
      developer.log('发送消息失败: $e', name: 'WebSocketService', error: e);
    }
  }

  /// 发送触摸事件
  void sendTouchEvent(int bellId, double intensity) {
    sendMessage(
      WebSocketMessage.touchEvent(bellId: bellId, intensity: intensity),
    );
  }

  /// 发送触觉反馈请求
  void sendHapticEvent(int effect, double intensity) {
    sendMessage(
      WebSocketMessage.hapticEvent(effect: effect, intensity: intensity),
    );
  }

  /// 启动心跳
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(AppConstants.heartbeatInterval, (timer) {
      if (isConnected) {
        sendMessage(WebSocketMessage.ping());
      }
    });
  }

  /// 停止心跳
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 安排重连
  void _scheduleReconnect() {
    if (!_shouldReconnect) return;

    _reconnectTimer?.cancel();
    _updateStatus(ConnectionStatus.reconnecting);

    _reconnectTimer = Timer(AppConstants.reconnectDelay, () {
      developer.log('尝试重新连接...', name: 'WebSocketService');
      _connect();
    });
  }

  /// 更新连接状态
  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController?.add(newStatus);
      developer.log('状态更新: ${newStatus.displayName}', name: 'WebSocketService');
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopHeartbeat();

    try {
      await _channel?.sink.close(1000); // Normal closure
      _channel = null;
    } catch (e) {
      developer.log('断开连接失败: $e', name: 'WebSocketService', error: e);
    }

    _updateStatus(ConnectionStatus.disconnected);
    developer.log('已断开连接', name: 'WebSocketService');
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _messageController?.close();
    _statusController?.close();
    _messageController = null;
    _statusController = null;
  }
}
