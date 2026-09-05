// new_short_video MCP stdio server。
// 将 tool/*.ps1 命令封装为 MCP tools，供 Trae 会话直接调用。
//
// 启动方式（被 MCP client 拉起）：
//   dart run tool/mcp/server.dart
//
// 协议：JSON-RPC 2.0 over stdio，Content-Length 帧。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _toolVersion = '0.1.0';

/// 项目根目录：以脚本自身位置上溯两级（tool/mcp -> 项目根），
/// 保证无论从哪个 cwd 启动都能定位 tool/*.ps1。
final _toolRoot = File.fromUri(Platform.script).parent.parent.parent;

// ---------------------------------------------------------------- MCP 定义

class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.schema,
    required this.run,
  });

  final String name;
  final String description;
  final Map<String, Object?> schema;
  final Future<Map<String, Object?>> Function(
    Map<String, Object?> args,
  ) run;
}

// ------------------------------------------------------------------ 输出

void _send(Object message) {
  final encoded = jsonEncode(message);
  final bytes = utf8.encode(encoded);
  final header = utf8.encode('Content-Length: ${bytes.length}\r\n\r\n');
  stdout.add(header);
  stdout.add(bytes);
  stdout.flush();
}

// ------------------------------------------------------------------ 工具

Future<Map<String, Object?>> _runPs1({
  required String script,
  required List<String> args,
}) async {
  final process = await Process.start(
    'pwsh',
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      p('tool/$script'),
      ...args,
    ],
    workingDirectory: _toolRoot.path,
    runInShell: false,
  );

  final stdoutBuf = StringBuffer();
  final stderrBuf = StringBuffer();
  process.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
  process.stderr.transform(utf8.decoder).listen(stderrBuf.write);
  final exitCode = await process.exitCode;

  return {
    'exit_code': exitCode,
    'stdout': stdoutBuf.toString(),
    'stderr': stderrBuf.toString(),
  };
}

String p(String path) => '${_toolRoot.path}${Platform.pathSeparator}$path';

final List<McpTool> _tools = [
  McpTool(
    name: 'app_logs',
    description:
        '从 Android 真机拉取 Flutter logcat。可选参数：device_id、tail(默认200)、since_seconds(>0时按时间窗)。返回原始日志文本。',
    schema: {
      'type': 'object',
      'properties': {
        'device_id': {'type': 'string', 'description': 'adb 设备 id，留空自动检测'},
        'tail': {'type': 'integer', 'description': '最近 N 行，默认 200'},
        'since_seconds': {'type': 'integer', 'description': '最近 N 秒窗口，默认 0（不启用）'},
      },
    },
    run: (args) => _runPs1(
      script: 'app-logs.ps1',
      args: [
        if (args['device_id'] != null)
          '-DeviceId',
          '${args['device_id']}',
        '-Tail',
        '${args['tail'] ?? 200}',
        if ((args['since_seconds'] as int? ?? 0) > 0)
          '-SinceSeconds',
          '${args['since_seconds']}',
      ],
    ),
  ),
  McpTool(
    name: 'app_run',
    description:
        '启动 fvm flutter run 到 Android 设备。可选：device_id、dart_define(可重复)、no_attach=true 时不绑定设备。阻塞直到进程退出，慎用。',
    schema: {
      'type': 'object',
      'properties': {
        'device_id': {'type': 'string'},
        'dart_define': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'no_attach': {'type': 'boolean'},
      },
    },
    run: (args) {
      final psArgs = <String>[];
      if (args['device_id'] != null) {
        psArgs.addAll(['-DeviceId', '${args['device_id']}']);
      }
      for (final d in (args['dart_define'] as List?) ?? const <Object?>[]) {
        psArgs.addAll(['-DartDefine', '$d']);
      }
      if (args['no_attach'] == true) {
        psArgs.add('-NoAttach');
      }
      return _runPs1(script: 'app-run.ps1', args: psArgs);
    },
  ),
  McpTool(
    name: 'app_analyze',
    description: '对客户端(flutter analyze)与服务端(dart analyze)做静态检查。',
    schema: {'type': 'object', 'properties': {}},
    run: (_) => _runPs1(script: 'app-analyze.ps1', args: const []),
  ),
  McpTool(
    name: 'server_start',
    description:
        '启动 Dart 文件服务。root_dir 缺省 E:/video/output，port 缺省 9090，log_file 可重定向输出。阻塞直到进程退出。',
    schema: {
      'type': 'object',
      'properties': {
        'root_dir': {'type': 'string'},
        'port': {'type': 'integer'},
        'log_file': {'type': 'string'},
      },
    },
    run: (args) {
      final psArgs = <String>[];
      if (args['root_dir'] != null) {
        psArgs.addAll(['-RootDir', '${args['root_dir']}']);
      }
      if (args['port'] != null) {
        psArgs.addAll(['-Port', '${args['port']}']);
      }
      if (args['log_file'] != null) {
        psArgs.addAll(['-LogFile', '${args['log_file']}']);
      }
      return _runPs1(script: 'server-start.ps1', args: psArgs);
    },
  ),
  McpTool(
    name: 'server_stop',
    description: '停止占用指定端口(缺省9090)的服务进程。',
    schema: {
      'type': 'object',
      'properties': {
        'port': {'type': 'integer'},
      },
    },
    run: (args) {
      final psArgs = <String>[];
      if (args['port'] != null) {
        psArgs.addAll(['-Port', '${args['port']}']);
      }
      return _runPs1(script: 'server-stop.ps1', args: psArgs);
    },
  ),
  McpTool(
    name: 'app_ui',
    description:
        '对 Android 真机执行 UI 原语。action=info 取分辨率与前台 app；swipe 需 x1,y1,x2,y2（可加 duration_ms/times）；tap 需 x1,y1；screenshot 保存到 out_file。无视觉反馈，仅执行。',
    schema: {
      'type': 'object',
      'properties': {
        'device_id': {'type': 'string'},
        'action': {'type': 'string', 'enum': ['info', 'swipe', 'tap', 'screenshot']},
        'x1': {'type': 'integer'},
        'y1': {'type': 'integer'},
        'x2': {'type': 'integer'},
        'y2': {'type': 'integer'},
        'duration_ms': {'type': 'integer'},
        'times': {'type': 'integer'},
        'out_file': {'type': 'string'},
      },
      'required': ['action'],
    },
    run: (args) {
      final psArgs = <String>[];
      void add(String key, Object? value) {
        if (value != null) psArgs.addAll(['-$key', '$value']);
      }

      add('Action', args['action']);
      add('DeviceId', args['device_id']);
      add('X1', args['x1']);
      add('Y1', args['y1']);
      add('X2', args['x2']);
      add('Y2', args['y2']);
      add('DurationMs', args['duration_ms']);
      add('Times', args['times']);
      add('OutFile', args['out_file']);
      return _runPs1(script: 'app-ui.ps1', args: psArgs);
    },
  ),
  McpTool(
    name: 'app_session',
    description:
        '一键调试会话：重启 app -> 预热滑动 -> 按 swipes 目标滑动 -> dump 该进程 flutter 日志到 log_file -> 可选截图到 screenshot_dir。用于无人值守重现现象并采集日志。',
    schema: {
      'type': 'object',
      'properties': {
        'device_id': {'type': 'string'},
        'swipes': {'type': 'integer', 'description': '目标滑动条数，默认 0'},
        'log_file': {'type': 'string', 'description': '日志落盘路径'},
        'screenshot_dir': {'type': 'string'},
      },
    },
    run: (args) {
      final psArgs = <String>[];
      if (args['device_id'] != null) {
        psArgs.addAll(['-DeviceId', '${args['device_id']}']);
      }
      psArgs.addAll(['-Swipes', '${args['swipes'] ?? 0}']);
      if (args['log_file'] != null) {
        psArgs.addAll(['-LogFile', '${args['log_file']}']);
      }
      if (args['screenshot_dir'] != null) {
        psArgs.addAll(['-ScreenshotDir', '${args['screenshot_dir']}']);
      }
      return _runPs1(script: 'app-session.ps1', args: psArgs);
    },
  ),
];

// ------------------------------------------------------------------- 主循环

Future<void> main() async {
  final controller = StreamController<String>();
  var buffer = <int>[];

  stdin.listen((chunk) {
    buffer.addAll(chunk);
    // 解析一个或多个 Content-Length 帧
    while (true) {
      final raw = utf8.decode(buffer, allowMalformed: true);
      final headerEnd = raw.indexOf('\r\n\r\n');
      if (headerEnd < 0) break;
      final header = raw.substring(0, headerEnd);
      final lengthMatch =
          RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false)
              .firstMatch(header);
      if (lengthMatch == null) {
        buffer.clear();
        break;
      }
      final length = int.parse(lengthMatch.group(1)!);
      final headerBytes = headerEnd + 4;
      if (buffer.length < headerBytes + length) break;

      final bodyBytes = buffer.sublist(headerBytes, headerBytes + length);
      controller.add(utf8.decode(bodyBytes));
      buffer.removeRange(0, headerBytes + length);
    }
  });

  await for (final line in controller.stream) {
    Map<String, Object?> request;
    try {
      request = jsonDecode(line) as Map<String, Object?>;
    } catch (_) {
      continue;
    }

    final method = request['method'] as String?;
    final id = request['id'];

    if (method == 'initialize') {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'short_video_mcp', 'version': _toolVersion},
        },
      });
      continue;
    }

    if (method == 'notifications/initialized') {
      continue; // 无操作
    }

    if (method == 'tools/list') {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'tools': [
            for (final tool in _tools)
              {
                'name': tool.name,
                'description': tool.description,
                'inputSchema': tool.schema,
              },
          ],
        },
      });
      continue;
    }

    if (method == 'tools/call') {
      final params = request['params'] as Map<String, Object?>? ?? {};
      final name = params['name'] as String? ?? '';
      final args = params['arguments'] as Map<String, Object?>? ?? {};
      final tool = _tools.where((t) => t.name == name).firstOrNull;
      if (tool == null) {
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'Unknown tool: $name'},
            ],
          },
        });
        continue;
      }

      try {
        final result = await tool.run(args);
        final text = [
          if ((result['stdout'] as String?)?.isNotEmpty ?? false)
            result['stdout'] as String,
          if ((result['stderr'] as String?)?.isNotEmpty ?? false)
            '[stderr]\n${result['stderr']}',
          if (result['exit_code'] != 0)
            '[exit=${result['exit_code']}]',
        ].join('\n');
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'isError': result['exit_code'] != 0,
            'content': [
              {'type': 'text', 'text': text.trim()},
            ],
          },
        });
      } catch (e) {
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'tool failed: $e'},
            ],
          },
        });
      }
      continue;
    }

    // 未知方法：回 methodNotFound
    _send({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': -32601, 'message': 'method not found: $method'},
    });
  }
}
