import 'dart:io';

import '../models/latency_sample.dart';

/// 将延迟样本导出为 CSV 文件（桌面端写入 Downloads）
class LatencyCsvExporter {
  static const int maxHistory = 500;

  static String buildCsvContent(List<LatencySample> samples) {
    final buffer = StringBuffer('${LatencySample.csvHeader().join(',')}\n');
    for (final sample in samples) {
      buffer.writeln(sample.toCsvRow().join(','));
    }
    return buffer.toString();
  }

  static Future<String?> writeToDownloads(List<LatencySample> samples) async {
    if (samples.isEmpty) return null;

    final content = buildCsvContent(samples);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'bianzhong_latency_$stamp.csv';

    Directory? dir;
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      dir = Directory('$userProfile\\Downloads');
    }
    dir ??= Directory.systemTemp;

    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final file = File('${dir.path}\\$fileName');
    await file.writeAsString(content);
    return file.path;
  }
}
