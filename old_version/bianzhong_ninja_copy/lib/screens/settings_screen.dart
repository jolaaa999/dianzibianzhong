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
              if (provider.reverbEnabled) ...[
                ListTile(
                  leading: const Icon(Icons.timer),
                  title: const Text('混响延迟'),
                  subtitle: Slider(
                    value: provider.reverbDelayMs.toDouble(),
                    min: 20,
                    max: 200,
                    divisions: 18,
                    label: '${provider.reverbDelayMs}ms',
                    onChanged: (v) => provider.setReverbDelayMs(v.round()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.waves),
                  title: const Text('混响湿声比例'),
                  subtitle: Slider(
                    value: provider.reverbWetMix,
                    min: 0.05,
                    max: 0.6,
                    divisions: 11,
                    label: provider.reverbWetMix.toStringAsFixed(2),
                    onChanged: provider.setReverbWetMix,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.looks_3),
                  title: const Text('混响触发复音数'),
                  subtitle: Slider(
                    value: provider.reverbMinVoices.toDouble(),
                    min: 2,
                    max: 8,
                    divisions: 6,
                    label: '${provider.reverbMinVoices}',
                    onChanged: (v) => provider.setReverbMinVoices(v.round()),
                  ),
                ),
              ],
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
                title: const Text('延迟指标'),
                subtitle: Text(provider.latencyMetrics.summary),
                trailing: Icon(
                  provider.latencyMetrics.meetsPrdTarget
                      ? Icons.check_circle
                      : Icons.info_outline,
                  color: provider.latencyMetrics.meetsPrdTarget
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重置延迟统计'),
                onTap: provider.resetLatencyMetrics,
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('导出延迟 CSV'),
                subtitle: Text('已记录 ${provider.latencyHistory.length} 条样本'),
                enabled: provider.latencyHistory.isNotEmpty,
                onTap: () => _exportLatencyCsv(context, provider),
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
              ListTile(
                leading: const Icon(Icons.fact_check),
                title: const Text('音频资源完整性检查'),
                subtitle: Text(_audioAuditSummary(provider)),
                onTap: () => _showAudioAuditDialog(context, provider),
              ),
              ListTile(
                leading: const Icon(Icons.clear_all),
                title: const Text('清除音色热替换'),
                subtitle: const Text('恢复所有 bellId 为默认采样映射'),
                onTap: () {
                  provider.clearBellAssetOverrides();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清除音色覆盖')),
                  );
                },
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

  Future<void> _exportLatencyCsv(
    BuildContext context,
    AppProvider provider,
  ) async {
    try {
      final path = await provider.exportLatencyCsv();
      if (!context.mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无延迟样本可导出')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出至 $path')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $error')),
      );
    }
  }

  String _audioAuditSummary(AppProvider provider) {
    final entries = provider.auditBellAssets();
    final missing = entries.where((entry) => entry.usesFallback).length;
    return missing == 0
        ? '60/60 bellId 均有可用采样'
        : '${entries.length - missing}/${entries.length} 有专用采样，$missing 个使用 fallback';
  }

  void _showAudioAuditDialog(BuildContext context, AppProvider provider) {
    final entries = provider.auditBellAssets();
    final missing = entries.where((entry) => entry.usesFallback).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('音频资源检查'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  missing.isEmpty
                      ? '全部 ${entries.length} 个 bellId 均有可用采样。'
                      : '以下 ${missing.length} 个 bellId 将回退到 bell_c3.wav：',
                ),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final entry in missing)
                    Text('• ${entry.label} (id=${entry.bellId}) → ${entry.resolvedAsset}'),
                ],
              ],
            ),
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
