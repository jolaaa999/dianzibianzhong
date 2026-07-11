import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sensor_data.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';

/// 连接界面
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _legacyWsController = TextEditingController(
    text: AppConstants.defaultWsUrl,
  );
  bool _isBusy = false;

  @override
  void dispose() {
    _legacyWsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接到数字编钟系统')),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGuideCard(provider),
              const SizedBox(height: 16),
              _buildUdpCard(provider),
              const SizedBox(height: 16),
              _buildLegacyWsCard(provider),
              if (provider.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      provider.errorMessage,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildGuideCard(AppProvider provider) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '推荐接入方式',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 12),
            _buildStep('1', '手机或电脑连接到编钟系统所在的同一局域网 (2.4GHz)'),
            _buildStep(
              '2',
              '击锤上电后自动连接已配网的 WiFi，或使用蓝牙/网页配网',
            ),
            _buildStep(
              '3',
              '应用监听 UDP ${AppConstants.defaultUdpPort} 广播，接收击锤姿态数据',
            ),
            _buildStep('4', '挥动击锤后，首页会显示姿态数据、活跃击锤和触发的编钟'),
            const SizedBox(height: 12),
            if (Platform.isWindows) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠ Windows 用户：首次运行时若收不到击锤数据，'
                  '请以管理员身份运行：\n'
                  'netsh advfirewall firewall add rule '
                  'name="BianzhongHammer UDP 3333" '
                  'dir=in action=allow protocol=UDP localport=3333',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              provider.connectionSummary,
              style: TextStyle(
                color: Colors.blue[900],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUdpCard(AppProvider provider) {
    final status = provider.connectionStatus;
    final isListening =
        status == ConnectionStatus.listening || provider.isConnected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'UDP 广播硬件输入',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('监听端口: ${AppConstants.defaultUdpPort}'),
            Text('推荐 WiFi: ${AppConstants.defaultSsid}'),
            Text('活跃击锤: ${provider.activeHammerSummary}'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isBusy
                  ? null
                  : () => _handleUdpAction(
                      provider,
                      restart: provider.isMonitoringHardware,
                    ),
              icon: Icon(isListening ? Icons.refresh : Icons.sensors),
              label: Text(isListening ? '重新监听 UDP 广播' : '开始监听 UDP 广播'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegacyWsCard(AppProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '兼容模式 WebSocket',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('仅在仍使用旧版 AP/WebSocket 固件时启用。'),
            const SizedBox(height: 16),
            TextField(
              controller: _legacyWsController,
              decoration: const InputDecoration(
                labelText: 'WebSocket 地址',
                hintText: 'ws://192.168.4.1:81',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isBusy
                  ? null
                  : () => _handleLegacyWsConnect(provider),
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('连接旧版 WebSocket'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            child: Text(number, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Future<void> _handleUdpAction(
    AppProvider provider, {
    required bool restart,
  }) async {
    setState(() {
      _isBusy = true;
    });

    try {
      if (restart) {
        await provider.restartHardwareDiscovery();
      } else {
        await provider.startHardwareDiscovery();
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('UDP 广播监听已启动'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _handleLegacyWsConnect(AppProvider provider) async {
    final url = _legacyWsController.text.trim();
    if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WebSocket 地址必须以 ws:// 或 wss:// 开头'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      await provider.connectLegacyWebSocket(url);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已发起 WebSocket 连接'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }
}
