import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bianzhong_app/services/udp_hammer_service.dart';

Map<String, Object?> _fixture({
  String type = 'cursor',
  int? proto = 1,
  int hammerId = 1,
  String deviceId = 'AABBCCDDEEFF-H1',
  double? force,
  String? tier,
  int? octave,
}) {
  return {
    'proto': proto,
    'type': type,
    'id': hammerId,
    'deviceId': deviceId,
    'force': force ?? 0.0,
    if (tier != null) 'tier': tier,
    if (octave != null) 'octave': octave,
    'yaw': 0.0,
    'pitch': 0.0,
    'roll': 0.0,
    'quaternion': {'w': 1.0, 'x': 0.0, 'y': 0.0, 'z': 0.0},
    'timestamp': 0,
  };
}

void main() {
  group('UdpHammerService.injectRawPayload', () {
    test('注入合法 strike proto=1 tier=medium', () async {
      final service = UdpHammerService();
      await service.start();

      final received = <UdpHammerMessage>[];
      final sub = service.messageStream.listen(received.add);

      service.injectRawPayload(jsonEncode(_fixture(
        type: 'strike',
        force: 0.7,
        tier: 'medium',
      )));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      service.stop();

      expect(received, hasLength(1));
      final msg = received.first;
      expect(msg.proto, 1);
      expect(msg.type, 'strike');
      expect(msg.tierIndex, 2); // medium=2
      expect(msg.deviceId.endsWith('-H1'), isTrue);
    });

    test('两支击锤按入网顺序分到左/右手', () async {
      final service = UdpHammerService();
      await service.start();

      service.injectRawPayload(jsonEncode(_fixture(
        deviceId: 'AABBCCDDEEFF-H1',
        hammerId: 1,
      )));
      service.injectRawPayload(jsonEncode(_fixture(
        deviceId: 'BBCCDDEEFF11-H2',
        hammerId: 2,
      )));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final hammers = service.activeHammers;
      expect(hammers, hasLength(2));
      expect(hammers.first.hand, HammerHand.left);
      expect(hammers.last.hand, HammerHand.right);
      expect(hammers.first.deviceId.endsWith('-H1'), isTrue);
      expect(hammers.last.deviceId.endsWith('-H2'), isTrue);

      service.stop();
    });

    test('已上桌的 deviceId 复用入座', () async {
      final service = UdpHammerService();
      await service.start();

      service.injectRawPayload(jsonEncode(_fixture(
        deviceId: 'AABBCCDDEEFF-H1',
        hammerId: 1,
      )));
      service.injectRawPayload(jsonEncode(_fixture(
        deviceId: 'AABBCCDDEEFF-H1',
        hammerId: 1,
      )));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.activeHammers, hasLength(1));

      service.stop();
    });

    test('缺少 type/id 时进入 error 流', () async {
      final service = UdpHammerService();
      await service.start();

      final errors = <Object>[];
      final errSub = service.errorStream.listen(errors.add);

      service.injectRawPayload('{"proto": 1, "yaw": 0}');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(errors, isNotEmpty);

      await errSub.cancel();
      service.stop();
    });
  });
}
