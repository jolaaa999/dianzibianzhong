import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:esp_blufi_for_flutter/esp_blufi_for_flutter.dart';
import 'package:flutter/foundation.dart';

import '../utils/constants.dart';

class BleProvisionDevice {
  final String id;
  final String name;

  const BleProvisionDevice({required this.id, required this.name});
}

class BleProvisionResult {
  final bool success;
  final String message;
  final String rawOutput;

  const BleProvisionResult({
    required this.success,
    required this.message,
    required this.rawOutput,
  });
}

class WifiScanResult {
  final List<String> networks;
  final String rawOutput;

  const WifiScanResult({required this.networks, required this.rawOutput});
}

class _BlufiEvent {
  final String key;
  final dynamic value;
  final String address;
  final String raw;

  const _BlufiEvent({
    required this.key,
    required this.value,
    required this.address,
    required this.raw,
  });

  factory _BlufiEvent.fromJsonString(String raw) {
    final decoded = json.decode(raw) as Map<String, dynamic>;
    return _BlufiEvent(
      key: decoded['key']?.toString() ?? '',
      value: decoded['value'],
      address: decoded['address']?.toString() ?? '',
      raw: raw,
    );
  }
}

class BleProvisioningService {
  final BlufiPlugin _mobileProvisioner = BlufiPlugin.instance;
  final StreamController<_BlufiEvent> _eventController =
      StreamController<_BlufiEvent>.broadcast();
  final List<String> _eventLog = <String>[];

  bool _callbacksBound = false;

  BleProvisioningService() {
    _bindCallbacks();
  }

  Future<List<BleProvisionDevice>> scanDevices() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return _scanMobileBlufiDevices();
    }
    return _scanDesktopDevices();
  }

  Future<BleProvisionResult> provision({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return const BleProvisionResult(
        success: false,
        message: '电脑端暂不支持 BluFi 配网，请使用手机 App 完成蓝牙配网',
        rawOutput: 'desktop-unsupported',
      );
    }

    _eventLog.clear();
    try {
      await _connectAndNegotiate(deviceId);

      final configureFuture = _waitForEvent(
        (event) =>
            event.address == deviceId &&
            event.key == 'configure_params' &&
            event.value?.toString() == '1',
        timeout: const Duration(seconds: 12),
      );

      await _mobileProvisioner.configProvision(
        username: ssid,
        password: password,
      );
      await configureFuture;

      final connected = await _waitForWifiConnected(deviceId);
      await _safeDisconnect();

      return BleProvisionResult(
        success: connected,
        message: connected ? '蓝牙配网成功，击锤将开始连接目标 WiFi' : '已下发 WiFi，但击锤尚未成功联网',
        rawOutput: _eventLog.join('\n'),
      );
    } catch (error) {
      await _safeDisconnect();
      return BleProvisionResult(
        success: false,
        message: '蓝牙配网失败: ${_summarizeError(error)}',
        rawOutput: _eventLog.join('\n'),
      );
    }
  }

  Future<WifiScanResult> scanWifiNetworks({
    required String deviceId,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      throw Exception('电脑端暂不支持通过 BluFi 扫描 WiFi，请使用手机 App');
    }

    _eventLog.clear();
    try {
      await _connectAndNegotiate(deviceId);
      final networks = await _collectWifiScanResults(deviceId);
      await _safeDisconnect();
      return WifiScanResult(
        networks: networks,
        rawOutput: _eventLog.join('\n'),
      );
    } catch (error) {
      await _safeDisconnect();
      throw Exception(_summarizeError(error));
    }
  }

  void _bindCallbacks() {
    if (_callbacksBound) {
      return;
    }
    _callbacksBound = true;

    _mobileProvisioner.onMessageReceived(
      successCallback: (String? data) {
        if (data == null || data.trim().isEmpty) {
          return;
        }
        _eventLog.add(data);
        try {
          _eventController.add(_BlufiEvent.fromJsonString(data));
        } catch (_) {
          _eventController.add(
            _BlufiEvent(
              key: 'raw',
              value: data,
              address: '',
              raw: data,
            ),
          );
        }
      },
      errorCallback: (String? error) {
        final raw = error ?? 'unknown-error';
        _eventLog.add(raw);
        _eventController.add(
          _BlufiEvent(
            key: 'plugin_error',
            value: raw,
            address: '',
            raw: raw,
          ),
        );
      },
    );
  }

  Future<List<BleProvisionDevice>> _scanMobileBlufiDevices() async {
    final devices = <String, BleProvisionDevice>{};
    final subscription = _eventController.stream.listen((event) {
      if (event.key != 'ble_scan_result' || event.value is! Map) {
        return;
      }

      final value = event.value as Map<dynamic, dynamic>;
      final address = value['address']?.toString() ?? '';
      final name = value['name']?.toString() ?? '';
      if (address.isEmpty || name.isEmpty) {
        return;
      }
      if (!name.startsWith(AppConstants.bleProvisionPrefix)) {
        return;
      }
      devices[address] = BleProvisionDevice(id: address, name: name);
    });

    try {
      await _mobileProvisioner.scanDeviceInfo(
        filterString: AppConstants.bleProvisionPrefix,
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      await _mobileProvisioner.stopScan();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    } finally {
      await subscription.cancel();
    }

    final result = devices.values.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
    return result;
  }

  Future<List<BleProvisionDevice>> _scanDesktopDevices() async {
    final commands = <String>[
      'timeout 12 bluetoothctl --timeout 10 scan on',
      'bluetoothctl devices',
      'bluetoothctl --timeout 1 scan off',
    ].join('\n');

    final result = await Process.run('bash', [
      '-lc',
      commands,
    ], runInShell: false);

    final devices = <String, BleProvisionDevice>{};
    final combined = '${result.stdout}\n${result.stderr}';
    for (final rawLine in const LineSplitter().convert(combined)) {
      final line = rawLine.trim();
      final match = RegExp(r'Device\s+([0-9A-F:]{17})\s+(.+)$').firstMatch(line);
      if (match == null) {
        continue;
      }
      final id = match.group(1)!;
      final name = match.group(2)!.trim();
      if (!name.startsWith(AppConstants.bleProvisionPrefix)) {
        continue;
      }
      devices[id] = BleProvisionDevice(id: id, name: name);
    }

    final list = devices.values.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
    return list;
  }

  Future<void> _connectAndNegotiate(String deviceId) async {
    await _mobileProvisioner.connectPeripheral(peripheralAddress: deviceId);
    await _waitForEvent(
      (event) =>
          event.address == deviceId &&
          event.key == 'peripheral_connect' &&
          event.value?.toString() == '1',
      timeout: const Duration(seconds: 8),
    );
    await _waitForEvent(
      (event) =>
          event.address == deviceId &&
          ((event.key == 'discover_service' &&
                  event.value?.toString() == '1') ||
              (event.key == 'blufi_connect_prepared' &&
                  event.value?.toString() == '1')),
      timeout: const Duration(seconds: 8),
    );

    await _mobileProvisioner.negotiateSecurity();
    await _waitForEvent(
      (event) =>
          event.address == deviceId &&
          event.key == 'negotiate_security' &&
          event.value?.toString() == '1',
      timeout: const Duration(seconds: 8),
    );
  }

  Future<List<String>> _collectWifiScanResults(String deviceId) async {
    final found = <String>{};
    final completer = Completer<List<String>>();
    Timer? doneTimer;

    void scheduleDone() {
      doneTimer?.cancel();
      doneTimer = Timer(const Duration(seconds: 2), () {
        if (!completer.isCompleted) {
          completer.complete(found.toList()..sort());
        }
      });
    }

    final subscription = _eventController.stream.listen((event) {
      if (event.address != deviceId) {
        return;
      }

      if (event.key == 'wifi_info' && event.value is Map) {
        final value = event.value as Map<dynamic, dynamic>;
        final ssid = value['ssid']?.toString().trim() ?? '';
        if (ssid.isNotEmpty) {
          found.add(ssid);
          scheduleDone();
        }
      } else if (event.key == 'wifi_info' &&
          event.value?.toString() == '0' &&
          !completer.isCompleted) {
        completer.completeError(Exception('击锤返回 WiFi 扫描失败'));
      } else if (event.key == 'receive_error_code' && !completer.isCompleted) {
        completer.completeError(
          Exception('击锤返回错误码 ${event.value}'),
        );
      }
    });

    try {
      await _mobileProvisioner.requestDeviceScan();
      Timer(const Duration(seconds: 6), () {
        if (!completer.isCompleted) {
          completer.complete(found.toList()..sort());
        }
      });
      return await completer.future;
    } finally {
      doneTimer?.cancel();
      await subscription.cancel();
    }
  }

  Future<bool> _waitForWifiConnected(String deviceId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      await _mobileProvisioner.requestDeviceStatus();
      try {
        final event = await _waitForEvent(
          (candidate) =>
              candidate.address == deviceId &&
              (candidate.key == 'device_wifi_connect' ||
                  candidate.key == 'receive_error_code'),
          timeout: const Duration(seconds: 2),
        );
        if (event.key == 'device_wifi_connect') {
          return event.value?.toString() == '1';
        }
        throw Exception('击锤返回错误码 ${event.value}');
      } on TimeoutException {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    return false;
  }

  Future<_BlufiEvent> _waitForEvent(
    bool Function(_BlufiEvent event) predicate, {
    required Duration timeout,
  }) async {
    final completer = Completer<_BlufiEvent>();
    late final StreamSubscription<_BlufiEvent> subscription;
    Timer? timer;

    subscription = _eventController.stream.listen((event) {
      if (event.key == 'plugin_error' && !completer.isCompleted) {
        completer.completeError(Exception(event.value.toString()));
        return;
      }
      if (predicate(event) && !completer.isCompleted) {
        completer.complete(event);
      }
    });

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('等待 BluFi 事件超时', timeout),
        );
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  Future<void> _safeDisconnect() async {
    try {
      await _mobileProvisioner.requestCloseConnection();
    } catch (_) {
      // ignore
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  String _summarizeError(Object error) {
    final message = error.toString();
    if (message.contains('TimeoutException')) {
      return '等待击锤响应超时，请确认设备已上电并靠近手机';
    }
    if (message.contains('peripheral_connect')) {
      return '蓝牙连接击锤失败';
    }
    if (message.contains('negotiate_security')) {
      return 'BluFi 安全协商失败';
    }
    return message;
  }
}
