import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';

/// 单次服务探测的结果分类，用于扫描结束后统计失败原因。
enum _ProbeOutcome {
  ok,
  unreachable,
  timeout,
  badHttp,
  badBody,
  error,
}

class ServerDiscoveryService {
  static const int _defaultPort = 9090;
  static const String _cachedEndpointKey = 'cached_server_endpoint';
  static const String _definedHostKey = 'VIDEO_SERVER_HOST';
  static const String _definedPortKey = 'VIDEO_SERVER_PORT';
  static const Duration _scanTimeout = Duration(seconds: 5);

  static const String _tag = 'Discovery';

  static int get defaultPort {
    const raw = int.fromEnvironment(_definedPortKey, defaultValue: 0);
    return raw > 0 ? raw : _defaultPort;
  }

  Future<ServerEndpoint> discoverServerHost() async {
    final prefs = await SharedPreferences.getInstance();
    final definedRaw = normalizeDefinedHost(
      const String.fromEnvironment(_definedHostKey),
    );
    final defined = definedRaw == null ? null : parseEndpoint(definedRaw);
    final cachedRaw = prefs.getString(_cachedEndpointKey);
    final cached = cachedRaw == null ? null : parseEndpoint(cachedRaw);

    AppLogger.info(_tag, 'discoverServerHost: defined=$definedRaw, '
        'cached=$cachedRaw');

    if (defined != null) {
      AppLogger.info(_tag, '尝试环境变量指定地址: $definedRaw');
      if (await _isValidServer(defined.host, defined.port)) {
        await _saveCache(prefs, defined);
        AppLogger.info(_tag, '环境变量地址验证成功: $definedRaw');
        return defined;
      }

      AppLogger.error(_tag, '环境变量地址不可用: $definedRaw');
      throw SocketException('指定服务地址不可用: $definedRaw');
    }

    if (cached != null) {
      AppLogger.info(_tag, '尝试缓存地址: $cachedRaw');
      if (await _isValidServer(cached.host, cached.port)) {
        AppLogger.info(_tag, '缓存地址验证成功，跳过扫描: $cachedRaw');
        return cached;
      }
      AppLogger.warn(_tag, '缓存地址不可达，需要重新扫描: $cachedRaw');
    } else {
      AppLogger.info(_tag, '无缓存地址，需要扫描');
    }

    final port = defaultPort;
    final directHost = await _probeHosts(
      buildDirectHostCandidates(isDesktop: _isDesktopPlatform),
      port,
    );
    if (directHost != null) {
      final endpoint = ServerEndpoint(host: directHost, port: port);
      await _saveCache(prefs, endpoint);
      AppLogger.info(_tag, '本机地址探测成功: $endpoint');
      return endpoint;
    }

    final subnetPrefixes = await _read192168SubnetPrefixes();
    if (subnetPrefixes.isEmpty) {
      AppLogger.error(_tag, '未识别到 192.168.x.x 局域网地址');
      throw const SocketException('未识别到 192.168.x.x 局域网地址');
    }

    AppLogger.info(
      _tag,
      '开始子网扫描: ${subnetPrefixes.map((p) => '$p.1-254').join(', ')} port=$port',
    );
    final host = await _scanSubnets(subnetPrefixes, port);
    if (host == null) {
      AppLogger.error(_tag, '子网扫描超时，未找到服务');
      throw const SocketException('5 秒内未找到可用的视频服务');
    }

    final endpoint = ServerEndpoint(host: host, port: port);
    await _saveCache(prefs, endpoint);
    AppLogger.info(_tag, '子网扫描成功: $endpoint');
    return endpoint;
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedEndpointKey);
  }

  Future<bool> hasCachedServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_cachedEndpointKey);
  }

  Future<void> _saveCache(SharedPreferences prefs, ServerEndpoint endpoint) async {
    await prefs.setString(_cachedEndpointKey, endpoint.toString());
  }

  /// 解析 "host" 或 "host:port"，端口缺省回退到 defaultPort。
  /// IPv6 必须用 [::1]:port 形式，这里不做特殊处理。
  static ServerEndpoint parseEndpoint(String raw) {
    final colonCount = ':'.allMatches(raw).length;
    if (colonCount == 1) {
      final idx = raw.indexOf(':');
      final host = raw.substring(0, idx);
      final port = int.tryParse(raw.substring(idx + 1)) ?? defaultPort;
      return ServerEndpoint(host: host, port: port);
    }
    return ServerEndpoint(host: raw, port: defaultPort);
  }

  static String? normalizeDefinedHost(String rawHost) {
    final normalized = rawHost.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static List<String> buildDirectHostCandidates({required bool isDesktop}) {
    if (!isDesktop) {
      return const <String>[];
    }

    return const <String>['127.0.0.1', 'localhost'];
  }

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// 枚举本机所有网卡，收集 192.168.x.x 网段（去重），
  /// 只扫 192.168 网段，不关心 10.x/172.x 等其它私网段。
  Future<List<String>> _read192168SubnetPrefixes() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    final prefixes = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final ip = address.address;
        final subnetPrefix = _to192168SubnetPrefix(ip);
        if (subnetPrefix == null) {
          continue;
        }
        if (!prefixes.contains(subnetPrefix)) {
          AppLogger.info(
            _tag,
            '候选网段: 接口=${interface.name} ip=$ip -> $subnetPrefix.1-254',
          );
          prefixes.add(subnetPrefix);
        }
      }
    }

    return prefixes;
  }

  String? _to192168SubnetPrefix(String ip) {
    final segments = ip.split('.');
    if (segments.length != 4) {
      return null;
    }

    final first = int.tryParse(segments[0]);
    final second = int.tryParse(segments[1]);
    final third = int.tryParse(segments[2]);
    if (first == null || second == null || third == null) {
      return null;
    }

    if (first != 192 || second != 168) {
      return null;
    }

    return '$first.$second.$third';
  }

  /// 跨多个网段交错扫描：host 编号对每个网段同时从 1 递增，
  /// 保证任一网段的服务端都会尽快被探测到。
  Future<String?> _scanSubnets(List<String> subnetPrefixes, int port) async {
    final completer = Completer<String?>();
    final stopwatch = Stopwatch()..start();
    const concurrency = 24;
    final totalHosts = subnetPrefixes.length * 254;
    var nextHost = 0;
    var activeWorkers = 0;
    var probedCount = 0;
    final outcomeCounts = <_ProbeOutcome, int>{};

    void record(_ProbeOutcome outcome) {
      outcomeCounts[outcome] = (outcomeCounts[outcome] ?? 0) + 1;
    }

    String summarize() {
      final parts = outcomeCounts.entries
          .map((e) => '${e.key.name}=${e.value}')
          .join(' ');
      return '探测 $probedCount 个 ($parts), '
          '耗时 ${stopwatch.elapsedMilliseconds}ms';
    }

    Future<void> worker() async {
      activeWorkers++;
      try {
        while (!completer.isCompleted &&
            stopwatch.elapsed < _scanTimeout &&
            nextHost < totalHosts) {
          final hostIndex = nextHost++;
          final prefix = subnetPrefixes[hostIndex ~/ 254];
          final host = '$prefix.${(hostIndex % 254) + 1}';
          final outcome = await _probeServer(host, port);
          probedCount++;
          record(outcome);
          if (outcome == _ProbeOutcome.ok) {
            AppLogger.info(_tag, '子网扫描命中: $host (${summarize()})');
            if (!completer.isCompleted) {
              completer.complete(host);
            }
            return;
          }
        }
      } finally {
        activeWorkers--;
        if (activeWorkers == 0 && !completer.isCompleted) {
          AppLogger.info(_tag, '子网扫描完毕未找到: ${summarize()}');
          completer.complete(null);
        }
      }
    }

    for (var i = 0; i < concurrency && i < totalHosts; i++) {
      unawaited(worker());
    }

    return completer.future.timeout(_scanTimeout, onTimeout: () {
      AppLogger.warn(_tag, '子网扫描超时: ${summarize()}');
      return null;
    });
  }

  Future<String?> _probeHosts(List<String> hosts, int port) async {
    if (hosts.isEmpty) return null;
    AppLogger.info(_tag, '本机地址探测: $hosts port=$port');
    for (final host in hosts.toSet()) {
      if (await _isValidServer(host, port)) {
        return host;
      }
    }
    AppLogger.info(_tag, '本机地址探测均失败');
    return null;
  }

  Future<bool> _isValidServer(String host, int port) async =>
      await _probeServer(host, port) == _ProbeOutcome.ok;

  Future<_ProbeOutcome> _probeServer(String host, int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 250);

    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/health',
      );
      final request = await client.getUrl(uri).timeout(
            const Duration(milliseconds: 350),
          );
      final response = await request.close().timeout(
            const Duration(milliseconds: 350),
          );
      if (response.statusCode != HttpStatus.ok) {
        return _ProbeOutcome.badHttp;
      }

      final body = await utf8.decodeStream(response);
      final data = jsonDecode(body);
      final valid = data is Map<String, dynamic> && data['msg'] != null;
      return valid ? _ProbeOutcome.ok : _ProbeOutcome.badBody;
    } on TimeoutException {
      return _ProbeOutcome.timeout;
    } on SocketException {
      return _ProbeOutcome.unreachable;
    } on HttpException {
      return _ProbeOutcome.badHttp;
    } on FormatException {
      return _ProbeOutcome.badBody;
    } catch (e) {
      AppLogger.warn(_tag, '_probeServer($host:$port) unexpected error: $e');
      return _ProbeOutcome.error;
    } finally {
      client.close(force: true);
    }
  }
}

class ServerEndpoint {
  const ServerEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}
