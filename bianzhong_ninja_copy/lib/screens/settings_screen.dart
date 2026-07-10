import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_demo_mode.dart';
import '../models/sensor_data.dart';
import '../providers/app_provider.dart';
import '../widgets/bell_grid_widget.dart';
import 'calibration_wizard_screen.dart';
import 'connection_screen.dart';
import '../utils/constants.dart';

/// 设置界面
class SettingsScreen extends StatelessWidget {
  final bool showAppBar;

  const SettingsScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final body = Consumer<AppProvider>(
        builder: (context, provider, child) {
          return ListView(
            children: [
              // 音频设置
              _buildSectionHeader('音频设置'),
              SwitchListTile(
                title: const Text('启用音频'),
                subtitle: const Text('播放编钟音效'),
                value: provider.audioEnabled,
                onChanged: provider.setAudioEnabled,
                secondary: const Icon(Icons.volume_up),
              ),
              SwitchListTile(
                title: const Text('厅堂混响'),
                subtitle: const Text('三音及以上时叠加微量延迟混响，模拟展厅声学'),
                value: provider.reverbEnabled,
                onChanged: provider.setReverbEnabled,
                secondary: const Icon(Icons.surround_sound),
              ),
              ListTile(
                leading: const Icon(Icons.volume_down),
                title: const Text('音量'),
                subtitle: Slider(
                  value: provider.volume,
                  onChanged: provider.setVolume,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(provider.volume * 100).toInt()}%',
                ),
                trailing: Text('${(provider.volume * 100).toInt()}%'),
              ),

              const Divider(),

              // 灵敏度设置
              _buildSectionHeader('传感器设置'),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('灵敏度'),
                subtitle: Slider(
                  value: provider.sensitivity,
                  onChanged: provider.setSensitivity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(provider.sensitivity * 100).toInt()}%',
                ),
                trailing: Text('${(provider.sensitivity * 100).toInt()}%'),
              ),

              const Divider(),

              // 连接信息
              _buildSectionHeader('配网与连接'),
              ListTile(
                leading: const Icon(Icons.input),
                title: const Text('输入模式'),
                subtitle: Text(provider.inputMode.displayName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ConnectionScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.router),
                title: const Text('配网与连接管理'),
                subtitle: const Text('连接击锤、配置 WiFi、查看 UDP 和 WebSocket'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ConnectionScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('硬件连接'),
                subtitle: Text(provider.connectionSummary),
              ),
              ListTile(
                leading: const Icon(Icons.signal_cellular_alt),
                title: const Text('连接状态'),
                subtitle: Text(provider.connectionStatus.displayName),
                trailing: Icon(
                  provider.isConnected ? Icons.check_circle : Icons.cancel,
                  color: provider.isConnected ? Colors.green : Colors.grey,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.message),
                title: const Text('已接收消息'),
                subtitle: Text('${provider.messageCount} 条'),
              ),
              ListTile(
                leading: const Icon(Icons.music_note),
                title: const Text('当前八度'),
                subtitle: Text('${provider.currentOctave}'),
              ),
              ListTile(
                leading: const Icon(Icons.gps_fixed),
                title: const Text('活跃击锤'),
                subtitle: Text(provider.activeHammerSummary),
              ),

              const Divider(),

              // 演示模式
              _buildSectionHeader('演示模式'),
              SwitchListTile(
                title: const Text('展厅演示模式'),
                subtitle: const Text('待机/attract loop 与 60 秒无操作自动回待机'),
                value: provider.demoModeEnabled,
                onChanged: provider.setDemoModeEnabled,
                secondary: const Icon(Icons.slideshow),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('重置演示'),
                subtitle: Text('当前: ${provider.demoMode.displayName}'),
                onTap: () => provider.resetDemoMode(),
              ),

              const Divider(),

              // 开发者选项
              _buildSectionHeader('开发者选项'),
              SwitchListTile(
                title: const Text('显示碰撞盒'),
                subtitle: const Text('调试模式下叠加显示隐性碰撞区域'),
                value: provider.debugShowHitBoxes,
                onChanged: provider.setDebugShowHitBoxes,
                secondary: const Icon(Icons.grid_on),
              ),
              ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('视觉敲击最低速度'),
                subtitle: Slider(
                  value: provider.visionStrikeDetector.minStrikeSpeed,
                  min: 0.2,
                  max: 2.0,
                  divisions: 18,
                  label: provider.visionStrikeDetector.minStrikeSpeed
                      .toStringAsFixed(2),
                  onChanged: provider.setVisionMinStrikeSpeed,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.pause_circle_outline),
                title: const Text('视觉悬停速度上限'),
                subtitle: Slider(
                  value: provider.visionStrikeDetector.hoverSpeedThreshold,
                  min: 0.05,
                  max: 0.8,
                  divisions: 15,
                  label: provider.visionStrikeDetector.hoverSpeedThreshold
                      .toStringAsFixed(2),
                  onChanged: provider.setVisionHoverSpeedThreshold,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('视觉敲击阈值摘要'),
                subtitle: Text(
                  '最低速度 ${provider.visionStrikeDetector.minStrikeSpeed.toStringAsFixed(2)} · '
                  '悬停 ${provider.visionStrikeDetector.hoverSpeedThreshold.toStringAsFixed(2)}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('编钟网格调试'),
                subtitle: const Text('BellGridWidget 八度选择器'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('编钟网格调试')),
                        body: BellGridWidget(
                          selectedOctave: provider.currentOctave,
                          getBellState: provider.getBellState,
                          onBellTapped: provider.onBellTapped,
                          onOctaveChanged: provider.setCurrentOctave,
                        ),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.center_focus_strong),
                title: const Text('重新校准'),
                subtitle: Text(
                  provider.calibrationCompleted ? '已完成校准' : '尚未完成校准',
                ),
                onTap: () async {
                  await provider.resetCalibration();
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CalibrationWizardScreen(),
                      ),
                    );
                  }
                },
              ),

              const Divider(),

              // 测试功能
              _buildSectionHeader('测试功能'),
              ListTile(
                leading: const Icon(Icons.send),
                title: const Text('发送测试消息'),
                subtitle: const Text('向ESP32发送测试消息'),
                enabled: provider.isConnected,
                onTap: () {
                  provider.sendTestMessage();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('测试消息已发送')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.music_note),
                title: const Text('测试所有编钟'),
                subtitle: const Text('依次播放所有编钟音效'),
                onTap: () => _testAllBells(context, provider),
              ),

              const Divider(),

              // 关于
              _buildSectionHeader('关于'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('应用版本'),
                subtitle: Text('1.0.0'),
              ),
              const ListTile(
                leading: Icon(Icons.code),
                title: Text('开发者'),
                subtitle: Text('虚拟数字编钟项目'),
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('项目说明'),
                subtitle: const Text('手机和电脑通过同一 WiFi 接收击锤 UDP 数据并演奏'),
                onTap: () => _showAboutDialog(context),
              ),
            ],
          );
        },
    );

    if (!showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: body,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  Future<void> _testAllBells(BuildContext context, AppProvider provider) async {
    // 测试当前八度的12个音符
    for (int octave = 1; octave <= 5; octave++) {
      final bells = BellMapping.getBellsByOctave(octave);
      for (var bell in bells) {
        provider.onBellTapped(bell.id, 0.8);
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('测试完成 - 已播放所有60个编钟')));
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于虚拟数字编钟'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '虚拟数字编钟是一个创新的交互式音乐项目，结合了：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('• ESP32-S3硬件平台'),
              Text('• BNO085 IMU传感器'),
              Text('• DRV2605触觉反馈驱动'),
              Text('• Flutter多平台应用'),
              Text('• WiFi/UDP联机'),
              SizedBox(height: 12),
              Text('通过挥动硬件锤子或点击屏幕，体验传统编钟的数字化演奏。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
