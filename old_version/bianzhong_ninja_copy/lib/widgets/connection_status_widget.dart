import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/sensor_data.dart';

/// 连接状态组件
class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final status = provider.connectionStatus;
        final color = _getStatusColor(status);
        final icon = _getStatusIcon(status);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border(
              bottom: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.displayName,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (provider.errorMessage.isNotEmpty)
                      Text(
                        provider.errorMessage,
                        style: TextStyle(color: color, fontSize: 12),
                      ),
                    if (provider.connectionSummary.isNotEmpty)
                      Text(
                        provider.connectionSummary,
                        style: TextStyle(color: color, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (status == ConnectionStatus.listening ||
                  status == ConnectionStatus.connecting ||
                  status == ConnectionStatus.reconnecting)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.listening:
        return Colors.blue;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return Colors.orange;
      case ConnectionStatus.disconnected:
        return Colors.grey;
      case ConnectionStatus.error:
        return Colors.red;
    }
  }

  IconData _getStatusIcon(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Icons.wifi;
      case ConnectionStatus.listening:
        return Icons.sensors;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return Icons.wifi_find;
      case ConnectionStatus.disconnected:
        return Icons.wifi_off;
      case ConnectionStatus.error:
        return Icons.error_outline;
    }
  }
}
