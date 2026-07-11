import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/ble_provisioning_service.dart';

class BleProvisionSheet extends StatefulWidget {
  const BleProvisionSheet({super.key});

  @override
  State<BleProvisionSheet> createState() => _BleProvisionSheetState();
}

class _BleProvisionSheetState extends State<BleProvisionSheet> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  BleProvisionDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AppProvider>();
      _ssidController.text = provider.provisioningTargetSsid;
      _passwordController.text = provider.provisioningTargetPassword;
      provider.loadCurrentWifiSsid();
      if (provider.bleDevices.isEmpty) {
        provider.scanBleProvisionDevices();
      }
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final devices = provider.bleDevices;
        if (_ssidController.text != provider.provisioningTargetSsid) {
          _ssidController.text = provider.provisioningTargetSsid;
          _ssidController.selection = TextSelection.fromPosition(
            TextPosition(offset: _ssidController.text.length),
          );
        }
        if (_passwordController.text != provider.provisioningTargetPassword) {
          _passwordController.text = provider.provisioningTargetPassword;
          _passwordController.selection = TextSelection.fromPosition(
            TextPosition(offset: _passwordController.text.length),
          );
        }
        if (devices.isEmpty) {
          _selectedDevice = null;
        } else if (_selectedDevice == null ||
            !devices.any((device) => device.id == _selectedDevice!.id)) {
          _selectedDevice = devices.first;
        }
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '蓝牙配网',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: provider.isBleScanning
                        ? null
                        : provider.scanBleProvisionDevices,
                    icon: provider.isBleScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('扫描名为 `BianzongHammer-XXXXXX` 的击锤，然后下发目标 WiFi。'),
              const SizedBox(height: 16),
              if (provider.currentWifiSsid.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('当前连接 WiFi：${provider.currentWifiSsid}'),
                      ),
                      TextButton(
                        onPressed: provider.isBleProvisioning
                            ? null
                            : () {
                                provider.setProvisioningTargetSsid(
                                  provider.currentWifiSsid,
                                );
                              },
                        child: const Text('使用'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                initialValue: _selectedDevice?.id,
                decoration: const InputDecoration(
                  labelText: '击锤蓝牙设备',
                  border: OutlineInputBorder(),
                ),
                items: devices
                    .map(
                      (device) => DropdownMenuItem<String>(
                        value: device.id,
                        child: Text(device.name),
                      ),
                    )
                    .toList(),
                onChanged: provider.isBleProvisioning
                    ? null
                    : (value) {
                        setState(() {
                          _selectedDevice = devices.firstWhere(
                            (device) => device.id == value,
                            orElse: () => devices.first,
                          );
                        });
                      },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: provider.isBleProvisioning || provider.isWifiScanning
                    ? null
                    : () => provider.scanProvisioningWifiNetworks(
                        deviceId: _selectedDevice?.id,
                      ),
                icon: provider.isWifiScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find),
                label: Text(
                  provider.isWifiScanning ? '正在扫描附近 WiFi...' : '搜索附近 WiFi',
                ),
              ),
              if (provider.nearbyWifiSsids.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: provider.nearbyWifiSsids.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final ssid = provider.nearbyWifiSsids[index];
                      final isCurrent = ssid == provider.currentWifiSsid;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: Icon(
                          isCurrent ? Icons.wifi : Icons.wifi_tethering,
                          size: 18,
                        ),
                        title: Text(ssid),
                        subtitle: isCurrent ? const Text('当前设备已连接') : null,
                        trailing: TextButton(
                          onPressed: provider.isBleProvisioning
                              ? null
                              : () {
                                  provider.setProvisioningTargetSsid(ssid);
                                },
                          child: const Text('选择'),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: '目标 WiFi 名称',
                  border: OutlineInputBorder(),
                ),
                onChanged: provider.setProvisioningTargetSsid,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '目标 WiFi 密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                onChanged: provider.setProvisioningTargetPassword,
              ),
              if (provider.bleProvisioningMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  provider.bleProvisioningMessage,
                  style: TextStyle(
                    color: provider.isBleProvisioning
                        ? Colors.blue[700]
                        : provider.bleProvisioningMessage.contains('成功')
                        ? Colors.green[700]
                        : Colors.red[700],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: provider.isBleProvisioning
                      ? null
                      : _handleProvision,
                  icon: provider.isBleProvisioning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_connected),
                  label: Text(
                    provider.isBleProvisioning ? '正在配网...' : '开始蓝牙配网',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleProvision() async {
    final provider = context.read<AppProvider>();
    final device = _selectedDevice;
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    if (device == null) {
      _showSnackBar('请先选择击锤蓝牙设备');
      return;
    }
    if (ssid.isEmpty) {
      _showSnackBar('请输入目标 WiFi 名称');
      return;
    }

    await provider.provisionBleDevice(
      deviceId: device.id,
      ssid: ssid,
      password: password,
    );

    if (!mounted) {
      return;
    }

    if (provider.lastBleProvisionSucceeded) {
      _showSnackBar('蓝牙配网成功，等待击锤上线');
      Navigator.of(context).pop();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
