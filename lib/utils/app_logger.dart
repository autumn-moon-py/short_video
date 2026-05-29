import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 全局日志收集器，同时输出到控制台和内存环形缓冲区。
/// 支持导出为文本文件，方便用户反馈问题。
///
/// 注意：仅限主 isolate 使用，不可在 compute() 或其他 isolate 中调用。
class AppLogger {
  AppLogger._();

  static const int _maxEntries = 2000;

  static final ListQueue<_LogEntry> _buffer = ListQueue<_LogEntry>(_maxEntries);
  static int _droppedCount = 0;

  static void debug(String tag, String message) {
    _emit('DEBUG', tag, message);
  }

  static void info(String tag, String message) {
    _emit('INFO', tag, message);
  }

  static void warn(String tag, String message) {
    _emit('WARN', tag, message);
  }

  static void error(String tag, String message, [Object? exception, StackTrace? stackTrace]) {
    final buf = StringBuffer(message);
    if (exception != null) {
      buf.write('\n  exception: $exception');
    }
    if (stackTrace != null) {
      buf.write('\n  stackTrace:\n${_takeLines(stackTrace.toString(), 8)}');
    }
    _emit('ERROR', tag, buf.toString());
  }

  static void _emit(String level, String tag, String message) {
    final now = DateTime.now();
    final entry = _LogEntry(now, level, tag, message);
    final line = entry.format();

    // 控制台输出
    debugPrint(line);

    // 环形缓冲区
    if (_buffer.length >= _maxEntries) {
      _buffer.removeFirst();
      _droppedCount++;
    }
    _buffer.addLast(entry);
  }

  /// 导出所有日志到临时目录下的文本文件，返回文件路径。
  static Future<String> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final fileName =
        'app_log_${now.year}${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.txt';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');

    final sb = StringBuffer();
    sb.writeln('=== 短视频 App 日志导出 ===');
    sb.writeln('导出时间: $now');
    if (_droppedCount > 0) {
      sb.writeln('早期日志已丢弃 $_droppedCount 条（缓冲区上限 $_maxEntries）');
    }
    sb.writeln();

    for (final entry in _buffer) {
      sb.writeln(entry.format());
    }

    await file.writeAsString(sb.toString(), flush: true);
    return file.path;
  }

  /// 获取当前缓冲区中的日志条数。
  static int get entryCount => _buffer.length;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _takeLines(String text, int maxLines) {
    final lines = text.split('\n');
    if (lines.length <= maxLines) return text;
    return '${lines.sublist(0, maxLines).join('\n')}\n  ... (${lines.length - maxLines} more lines)';
  }
}

class _LogEntry {
  _LogEntry(this.timestamp, this.level, this.tag, this.message);

  final DateTime timestamp;
  final String level;
  final String tag;
  final String message;

  String format() {
    final ts =
        '${_two(timestamp.hour)}:${_two(timestamp.minute)}:'
        '${_two(timestamp.second)}.${_three(timestamp.millisecond)}';
    return '[$ts] $level/$tag: $message';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _three(int n) => n.toString().padLeft(3, '0');
}
