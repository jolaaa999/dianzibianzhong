import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WifiInfoService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.bianzhong_app/wifi_info',
  );

  Future<String?> getCurrentSsid() async {
    if (kIsWeb) {
      return null;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final value = await _channel.invokeMethod<String>('getCurrentSsid');
        return _sanitizeSsid(value);
      } catch (_) {
        return null;
      }
    }

    if (Platform.isLinux) {
      return _getCurrentSsidLinux();
    }

    if (Platform.isWindows) {
      return _getCurrentSsidWindows();
    }

    if (Platform.isMacOS) {
      return _getCurrentSsidMacOS();
    }

    return null;
  }

  Future<String?> _getCurrentSsidLinux() async {
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'ACTIVE,SSID',
        'device',
        'wifi',
        'list',
      ], runInShell: false);
      final output = '${result.stdout}';
      for (final rawLine in const LineSplitter().convert(output)) {
        final line = rawLine.trim();
        if (!line.startsWith('yes:')) {
          continue;
        }
        final ssid = line.substring(4).trim();
        return _sanitizeSsid(ssid);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String?> _getCurrentSsidWindows() async {
    try {
      // netsh wlan show interfaces - outputs current WiFi connection details
      final result = await Process.run('netsh', [
        'wlan',
        'show',
        'interfaces',
      ], runInShell: false);
      final output = '${result.stdout}';
      for (final rawLine in const LineSplitter().convert(output)) {
        final line = rawLine.trim();
        // Look for "SSID" or "SSID                   : MyWiFiName"
        if (line.toUpperCase().startsWith('SSID')) {
          final colonIndex = line.indexOf(':');
          if (colonIndex >= 0 && colonIndex + 1 < line.length) {
            final ssid = line.substring(colonIndex + 1).trim();
            return _sanitizeSsid(ssid);
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String?> _getCurrentSsidMacOS() async {
    try {
      // /System/Library/PrivateFrameworks/Apple80211.framework
      final result = await Process.run('networksetup', [
        '-getairportnetwork',
        'en0',
      ], runInShell: false);
      final output = '${result.stdout}';
      final match =
          RegExp(r'Current Wi-Fi Network:\s*(.+)$', multiLine: true)
              .firstMatch(output);
      if (match != null) {
        return _sanitizeSsid(match.group(1));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<List<String>> scanNearbyWifiNames() async {
    if (kIsWeb) {
      return const [];
    }

    if (Platform.isLinux) {
      return _scanNearbyWifiLinux();
    }

    if (Platform.isWindows) {
      return _scanNearbyWifiWindows();
    }

    if (Platform.isMacOS) {
      return _scanNearbyWifiMacOS();
    }

    return const [];
  }

  Future<List<String>> _scanNearbyWifiLinux() async {
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'SSID',
        'device',
        'wifi',
        'list',
        '--rescan',
        'yes',
      ], runInShell: false);
      final output = '${result.stdout}';
      final names = <String>{};
      for (final rawLine in const LineSplitter().convert(output)) {
        final ssid = _sanitizeSsid(rawLine.trim());
        if (ssid != null && ssid.isNotEmpty) {
          names.add(ssid);
        }
      }
      final list = names.toList(growable: false)..sort();
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _scanNearbyWifiWindows() async {
    try {
      // netsh wlan show networks mode=bssid - lists all visible WiFi networks
      final result = await Process.run('netsh', [
        'wlan',
        'show',
        'networks',
        'mode=bssid',
      ], runInShell: false);
      final output = '${result.stdout}';
      final names = <String>{};
      for (final rawLine in const LineSplitter().convert(output)) {
        final line = rawLine.trim();
        // Look for "SSID 1 : MyWiFiName" or "SSID N : MyWiFiName"
        if (line.toUpperCase().startsWith('SSID')) {
          final colonIndex = line.indexOf(':');
          if (colonIndex >= 0 && colonIndex + 1 < line.length) {
            // Strip leading digits (e.g., "SSID 1 :" -> index after colon)
            final ssid = _sanitizeSsid(line.substring(colonIndex + 1).trim());
            if (ssid != null && ssid.isNotEmpty) {
              names.add(ssid);
            }
          }
        }
      }
      final list = names.toList(growable: false)..sort();
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _scanNearbyWifiMacOS() async {
    // macOS airport 输出解析较复杂且格式不固定；暂时返回空。
    // 桌面端用户可使用击锤 SoftAP 网页 (http://192.168.4.1) 查看附近 WiFi。
    return const [];
  }

  String? _sanitizeSsid(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '<unknown ssid>') {
      return null;
    }
    if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }
}
