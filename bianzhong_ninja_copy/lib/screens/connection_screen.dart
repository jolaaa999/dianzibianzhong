import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_demo_mode.dart';
import '../models/sensor_data.dart';
import '../models/vision_stick_frame.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import '../widgets/ble_provision_sheet.dart';

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
  final _visionWsController = TextEditingController(
    text: AppConstants.defaultVisionWsUrl,
  );
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _visionWsController.text = context.read<AppProvider>().visionWsUrl;
    });
  }

  @override
  void dispose() {
    _legacyWsController.dispose();
    _visionWsController.dispose();
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
              _buildInputModeCard(provider),
              const SizedBox(height: 16),
              _buildGuideCard(provider),
              const SizedBox(height: 16),
              if (provider.inputMode == InputMode.imu) ...[
                _buildUdpCard(provider),
                const SizedBox(height: 16),
                _buildBleCard(context, provider),
                const SizedBox(height: 16),
              ],
              if (provider.inputMode == InputMode.vision)
                _buildVisionCard(provider),
              if (provider.inputMode == InputMode.imu) ...[
                const SizedBox(height: 16),
                _buildLegacyWsCard(provider),
              ],
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

  Widget _buildInputModeCard(AppProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入模式',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...InputMode.values.map(
              (mode) => RadioListTile<InputMode>(
                title: Text(mode.displayName),
                value: mode,
                groupValue: provider.inputMode,
                onChanged: _isBusy
                    ? null
                    : (value) {
                        if (value != null) provider.setInputMode(value);
                      },
              ),
            ),
          ],
        ),
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
              provider.inputMode == InputMode.vision
                  ? '视觉追踪接入（方案一）'
                  : '推荐接入方式',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 12),
            if (provider.inputMode == InputMode.vision) ...[
              _buildStep('1', '启动 Python/OpenCV 视觉追踪服务'),
              _buildStep('2', '连接 WebSocket 接收 stick 坐标'),
              _buildStep('3', '挥动敲击棒，舞台显示光标并触发编钟'),
            ] else if (provider.inputMode == InputMode.touchOnly) ...[
              _buildStep('1', '仅使用屏幕触控/鼠标敲击编钟'),
              _buildStep('2', '适用于 UI 调试，无需硬件'),
            ] else ...[
              _buildStep('1', '手机或电脑连接到编钟系统所在的同一局域网'),
              _buildStep(
                '2',
                '应用监听 UDP ${AppConstants.defaultUdpPort} 广播，等待 ESP32 击锤上报',
              ),
              _buildStep('3', '挥动击锤后，首页会显示姿态数据、活跃击锤和触发的编钟'),
            ],
            const SizedBox(height: 12),
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

  Widget _buildVisionCard(AppProvider provider) {
    final connected = provider.visionStatus == ConnectionStatus.connected;
    final signalLost = provider.visionSignalLost;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '视觉追踪（方案一）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _visionWsController,
              decoration: const InputDecoration(
                labelText: 'WebSocket 地址',
                hintText: 'ws://127.0.0.1:8765',
                prefixIcon: Icon(Icons.videocam),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (signalLost && connected)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '追踪信号丢失',
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            const SizedBox(height: 12),
            ...provider.stickFrames.map(_buildStickFrameTile),
            if (provider.stickFrames.isEmpty)
              Text(
                '等待 stick 坐标...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBusy
                        ? null
                        : () => _handleVisionConnect(provider),
                    icon: const Icon(Icons.link),
                    label: Text(connected ? '重新连接' : '连接视觉追踪'),
                  ),
                ),
                if (connected) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _isBusy
                        ? null
                        : () => provider.disconnectVisionTracking(),
                    child: const Text('断开'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickFrameTile(VisionStickFrame frame) {
    final label = frame.isVisible
        ? '棒${frame.stickId}: x=${frame.x.toStringAsFixed(2)} '
            'y=${frame.y.toStringAsFixed(2)} '
            'conf=${frame.confidence.toStringAsFixed(2)}'
        : '棒${frame.stickId}: 离屏';
    return ListTile(
      dense: true,
      leading: Icon(
        frame.isVisible ? Icons.gps_fixed : Icons.gps_off,
        color: frame.isVisible ? Colors.green : Colors.orange,
        size: 20,
      ),
      title: Text(label, style: const TextStyle(fontSize: 13)),
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

  Widget _buildBleCard(BuildContext context, AppProvider provider) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bluetooth),
        title: const Text('蓝牙配网'),
        subtitle: const Text('通过 BluFi 为击锤配置 WiFi'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          if (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请使用手机 App 完成蓝牙配网')),
            );
            return;
          }
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const BleProvisionSheet(),
          );
        },
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

  Future<void> _handleVisionConnect(AppProvider provider) async {
    final url = _visionWsController.text.trim();
    if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WebSocket 地址必须以 ws:// 或 wss:// 开头'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      await provider.connectVisionTracking(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已发起视觉追踪连接'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handleUdpAction(
    AppProvider provider, {
    required bool restart,
  }) async {
    setState(() => _isBusy = true);
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
      if (mounted) setState(() => _isBusy = false);
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

    setState(() => _isBusy = true);
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
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
