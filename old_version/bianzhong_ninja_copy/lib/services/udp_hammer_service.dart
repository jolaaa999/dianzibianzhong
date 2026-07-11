import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../utils/constants.dart';

enum HammerHand { left, right }

extension HammerHandLabel on HammerHand {
  String get displayName => this == HammerHand.left ? '左手' : '右手';
}

class ActiveHammerInfo {
  final String deviceId;
  final int hammerId;
  final int seatIndex;
  final HammerHand hand;

  const ActiveHammerInfo({
    required this.deviceId,
    required this.hammerId,
    required this.seatIndex,
    required this.hand,
  });

  String get displayLabel => '${hand.displayName}${(seatIndex ~/ 2) + 1}';
  String get shortDeviceId =>
      deviceId.length <= 6 ? deviceId : deviceId.substring(deviceId.length - 6);
}

class UdpHammerMessage {
  final String type;
  final int hammerId;
  final String deviceId;
  final int seatIndex;
  final HammerHand hand;
  final int? octave;
  final double yaw;
  final double pitch;
  final double roll;
  final double quaternionW;
  final double quaternionX;
  final double quaternionY;
  final double quaternionZ;
  final double force;
  final int? timestampUs;

  const UdpHammerMessage({
    required this.type,
    required this.hammerId,
    required this.deviceId,
    required this.seatIndex,
    required this.hand,
    this.octave,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.quaternionW,
    required this.quaternionX,
    required this.quaternionY,
    required this.quaternionZ,
    this.force = 0.0,
    this.timestampUs,
  });

  bool get isStrike => type == 'strike';
}

class UdpHammerService {
  RawDatagramSocket? _socket;
  Timer? _timeoutTimer;
  bool _isListening = false;

  final Map<String, _ActiveHammerPresence> _presenceByDeviceId = {};
  final List<ActiveHammerInfo> _activeHammers = [];
  final Set<String> _overflowDeviceIds = {};
  final StreamController<UdpHammerMessage> _messageController =
      StreamController<UdpHammerMessage>.broadcast();
  final StreamController<List<ActiveHammerInfo>> _activeHammerController =
      StreamController<List<ActiveHammerInfo>>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();
  int _nextSeatIndex = 0;

  Stream<UdpHammerMessage> get messageStream => _messageController.stream;
  Stream<List<ActiveHammerInfo>> get activeHammerStream =>
      _activeHammerController.stream;
  Stream<Object> get errorStream => _errorController.stream;

  bool get isListening => _isListening;
  Set<int> get activeHammerIds =>
      _activeHammers.map((hammer) => hammer.hammerId).toSet();
  List<ActiveHammerInfo> get activeHammers => List.unmodifiable(_activeHammers);

  Future<void> start() async {
    if (_isListening) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.defaultUdpPort,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen(_handleSocketEvent, onError: _handleError);

      _timeoutTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _expireInactiveHammers(),
      );

      _isListening = true;
      _activeHammerController.add(activeHammers);
      developer.log(
        'UDP hammer listener started on :${AppConstants.defaultUdpPort}',
        name: 'UdpHammerService',
      );
    } catch (error) {
      _handleError(error);
      rethrow;
    }
  }

  Future<void> restart() async {
    stop();
    await start();
  }

  void stop() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _socket?.close();
    _socket = null;
    _presenceByDeviceId.clear();
    _activeHammers.clear();
    _overflowDeviceIds.clear();
    _nextSeatIndex = 0;
    _isListening = false;
    _activeHammerController.add(activeHammers);
  }

  void dispose() {
    stop();
    _messageController.close();
    _activeHammerController.close();
    _errorController.close();
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket?.receive();
    if (datagram == null) return;

    try {
      final raw = utf8.decode(datagram.data, allowMalformed: true);
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('UDP payload is not a JSON object');
      }

      final type = json['type'] as String?;
      final hammerId = (json['id'] as num?)?.toInt();
      if (type == null || hammerId == null) {
        throw const FormatException('UDP payload missing type or id');
      }
      if (hammerId < 1 || hammerId > 12) {
        throw FormatException('Invalid hammer id: $hammerId');
      }

      final rawDeviceId = (json['deviceId'] as String?)?.trim();
      final deviceId = (rawDeviceId != null && rawDeviceId.isNotEmpty)
          ? rawDeviceId
          : datagram.address.address;
      final hammerInfo = _touchDevice(deviceId, hammerId);
      if (hammerInfo == null) {
        return;
      }
      final quaternion = json['quaternion'] as Map<String, dynamic>?;

      final message = UdpHammerMessage(
        type: type,
        hammerId: hammerId,
        deviceId: deviceId,
        seatIndex: hammerInfo.seatIndex,
        hand: hammerInfo.hand,
        octave: (json['octave'] as num?)?.toInt(),
        yaw: (json['yaw'] as num?)?.toDouble() ?? 0.0,
        pitch: (json['pitch'] as num?)?.toDouble() ?? 0.0,
        roll: (json['roll'] as num?)?.toDouble() ?? 0.0,
        quaternionW: (quaternion?['w'] as num?)?.toDouble() ?? 1.0,
        quaternionX: (quaternion?['x'] as num?)?.toDouble() ?? 0.0,
        quaternionY: (quaternion?['y'] as num?)?.toDouble() ?? 0.0,
        quaternionZ: (quaternion?['z'] as num?)?.toDouble() ?? 0.0,
        force: ((json['force'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
        timestampUs: (json['timestamp'] as num?)?.toInt(),
      );

      _messageController.add(message);
    } catch (error) {
      _handleError(error);
    }
  }

  void _expireInactiveHammers() {
    final now = DateTime.now();
    _presenceByDeviceId.removeWhere(
      (_, presence) =>
          now.difference(presence.lastSeen) > AppConstants.hammerTimeout,
    );
    _syncActiveHammers();
  }

  ActiveHammerInfo? _touchDevice(String deviceId, int hammerId) {
    final now = DateTime.now();
    final existing = _presenceByDeviceId[deviceId];
    if (existing != null) {
      existing
        ..hammerId = hammerId
        ..lastSeen = now;
      _syncActiveHammers();
      return existing.toInfo();
    }

    if (_presenceByDeviceId.length >= AppConstants.maxHammerCount) {
      if (_overflowDeviceIds.add(deviceId)) {
        _handleError(
          StateError('最多支持 ${AppConstants.maxHammerCount} 个击锤，已忽略设备 $deviceId'),
        );
      }
      return null;
    }

    _overflowDeviceIds.remove(deviceId);
    final seatIndex = _nextSeatIndex++;
    final presence = _ActiveHammerPresence(
      deviceId: deviceId,
      hammerId: hammerId,
      seatIndex: seatIndex,
      hand: seatIndex.isEven ? HammerHand.left : HammerHand.right,
      lastSeen: now,
    );
    _presenceByDeviceId[deviceId] = presence;
    _syncActiveHammers();
    return presence.toInfo();
  }

  void _syncActiveHammers() {
    final next =
        _presenceByDeviceId.values.map((presence) => presence.toInfo()).toList()
          ..sort((left, right) => left.seatIndex.compareTo(right.seatIndex));
    if (_sameHammerInfos(_activeHammers, next)) return;

    _activeHammers
      ..clear()
      ..addAll(next);
    _activeHammerController.add(activeHammers);
  }

  void _handleError(Object error) {
    developer.log(
      'UDP hammer listener error',
      name: 'UdpHammerService',
      error: error,
    );
    _errorController.add(error);
  }

  bool _sameHammerInfos(
    List<ActiveHammerInfo> left,
    List<ActiveHammerInfo> right,
  ) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.deviceId != b.deviceId ||
          a.hammerId != b.hammerId ||
          a.seatIndex != b.seatIndex ||
          a.hand != b.hand) {
        return false;
      }
    }
    return true;
  }
}

class _ActiveHammerPresence {
  final String deviceId;
  int hammerId;
  final int seatIndex;
  final HammerHand hand;
  DateTime lastSeen;

  _ActiveHammerPresence({
    required this.deviceId,
    required this.hammerId,
    required this.seatIndex,
    required this.hand,
    required this.lastSeen,
  });

  ActiveHammerInfo toInfo() {
    return ActiveHammerInfo(
      deviceId: deviceId,
      hammerId: hammerId,
      seatIndex: seatIndex,
      hand: hand,
    );
  }
}
