import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 摄像头 MJPEG/快照预览（连接 Python 视觉服务的 /snapshot 端点）
class CameraPreviewPanel extends StatefulWidget {
  final String snapshotUrl;
  final double height;

  const CameraPreviewPanel({
    super.key,
    this.snapshotUrl = AppConstants.defaultVisionSnapshotUrl,
    this.height = 180,
  });

  @override
  State<CameraPreviewPanel> createState() => _CameraPreviewPanelState();
}

class _CameraPreviewPanelState extends State<CameraPreviewPanel> {
  Timer? _refreshTimer;
  int _tick = 0;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = '${widget.snapshotUrl}?t=$_tick';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: widget.height,
        color: Colors.black87,
        child: _loadFailed
            ? Center(
                child: Text(
                  '摄像头预览不可用\n请启动 vision_tracking_server.py',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              )
            : Image.network(
                uri,
                fit: BoxFit.cover,
                width: double.infinity,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) {
                  if (!_loadFailed) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _loadFailed = true);
                    });
                  }
                  return Center(
                    child: Text(
                      '加载预览中…',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  );
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
