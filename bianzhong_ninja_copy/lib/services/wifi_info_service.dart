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
    }

    return null;
  }

  Future<List<String>> scanNearbyWifiNames() async {
    if (kIsWeb) {
      return const [];
    }

    if (Platform.isLinux) {
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
