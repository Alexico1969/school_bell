import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CrashLogger {
  static const _fileName = 'crash_log.txt';
  static const _maxBytes = 50000;

  static Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> log(Object error, StackTrace stack) async {
    try {
      final file = await _logFile();
      final timestamp = DateTime.now().toIso8601String();
      final entry = '[$timestamp]\n$error\n\n$stack\n${'─' * 60}\n\n';

      String existing = '';
      if (await file.exists()) {
        existing = await file.readAsString();
        if (existing.length + entry.length > _maxBytes) {
          existing = existing.substring(
            (existing.length + entry.length - _maxBytes).clamp(0, existing.length),
          );
        }
      }
      await file.writeAsString(existing + entry);
    } catch (_) {
      // don't crash the crash logger
    }
  }

  static Future<String> read() async {
    try {
      final file = await _logFile();
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _logFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
