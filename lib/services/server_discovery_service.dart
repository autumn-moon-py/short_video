import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';

class ServerDiscoveryService {
  static const int serverPort = 9090;
  static const String _cachedHostKey = 'cached_server_host';
  static const String _definedHostKey = 'VIDEO_SERVER_HOST';
  static const Duration _scanTimeout = Duration(seconds: 5);

  static const String _tag = 'Discovery';

  Future<String> discoverServerHost() async {
    final prefs = await SharedPreferences.getInstance();
    final definedHost = normalizeDefinedHost(
      const String.fromEnvironment(_definedHostKey),
    );
    final cachedHost = prefs.getString(_cachedHostKey);

    AppLogger.info(_tag, 'discoverServerHost: definedHost=$definedHost, '
        'cachedHost=$cachedHost');

    if (definedHost != null) {
      AppLogger.info(_tag, '尝试环境变量指定地址: $definedHost');
      if (await _isValidServer(definedHost)) {
        await prefs.setString(_cachedHostKey, definedHost);
        AppLogger.info(_tag, '环境变量地址验证成功: $definedHost');
        return definedHost;
      }

      AppLogger.error(_tag, '环境变量地址不可用: $definedHost');
      throw SocketException('指定服务地址不可用: $definedHost');
    }

    if (cachedHost != null) {
      AppLogger.info(_tag, '尝试缓存地址: $cachedHost');
      if (await _isValidServer(cachedHost)) {
        AppLogger.info(_tag, '缓存地址验证成功，跳过扫描: $cachedHost');
        return cachedHost;
      }
      AppLogger.warn(_tag, '缓存地址不可达，需要重新扫描: $cachedHost');
    } else {
      AppLogger.info(_tag, '无缓存地址，需要扫描');
    }

    final directHost = await _probeHosts(
      buildDirectHostCandidates(isDesktop: _isDesktopPlatform),
    );
    if (directHost != null) {
      await prefs.setString(_cachedHostKey, directHost);
      AppLogger.info(_tag, '本机地址探测成功: $directHost');
      return directHost;
    }

    final subnetPrefix = await _readSubnetPrefix();
    if (subnetPrefix == null) {
      AppLogger.error(_tag, '未识别到可扫描的局域网 IPv4 地址');
      throw const SocketException('未识别到可扫描的局域网 IPv4 地址');
    }

    AppLogger.info(_tag, '开始子网扫描: $subnetPrefix.1-254');
    final host = await _scanSubnet(subnetPrefix);
    if (host == null) {
      AppLogger.error(_tag, '子网扫描超时，未找到服务');
      throw const SocketException('5 秒内未找到可用的视频服务');
    }

    await prefs.setString(_cachedHostKey, host);
    AppLogger.info(_tag, '子网扫描成功: $host');
    return host;
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedHostKey);
  }

  Future<bool> hasCachedServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_cachedHostKey);
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

  Future<String?> _readSubnetPrefix() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final ip = address.address;
        final subnetPrefix = _toPrivateSubnetPrefix(ip);
        if (subnetPrefix == null) {
          continue;
        }

        return subnetPrefix;
      }
    }

    return null;
  }

  String? _toPrivateSubnetPrefix(String ip) {
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

    final is192 = first == 192 && second == 168;
    final is10 = first == 10;
    final is172 = first == 172 && second >= 16 && second <= 31;
    if (!is192 && !is10 && !is172) {
      return null;
    }

    return '$first.$second.$third';
  }

  Future<String?> _scanSubnet(String subnetPrefix) async {
    final completer = Completer<String?>();
    final stopwatch = Stopwatch()..start();
    const concurrency = 24;
    var nextHost = 1;
    var activeWorkers = 0;
    var probedCount = 0;

    Future<void> worker() async {
      activeWorkers++;
      try {
        while (!completer.isCompleted &&
            stopwatch.elapsed < _scanTimeout &&
            nextHost <= 254) {
          final host = '$subnetPrefix.${nextHost++}';
          final valid = await _isValidServer(host);
          probedCount++;
          if (valid) {
            AppLogger.info(_tag, '子网扫描命中: $host '
                '(已探测 $probedCount 个, 耗时 ${stopwatch.elapsedMilliseconds}ms)');
            if (!completer.isCompleted) {
              completer.complete(host);
            }
            return;
          }
        }
      } finally {
        activeWorkers--;
        if (activeWorkers == 0 && !completer.isCompleted) {
          AppLogger.info(_tag, '子网扫描完毕未找到: '
              '探测 $probedCount 个, 耗时 ${stopwatch.elapsedMilliseconds}ms');
          completer.complete(null);
        }
      }
    }

    for (var i = 0; i < concurrency && i < 254; i++) {
      unawaited(worker());
    }

    return completer.future.timeout(_scanTimeout, onTimeout: () {
      AppLogger.warn(_tag, '子网扫描超时: '
          '已探测 $probedCount 个, 耗时 ${stopwatch.elapsedMilliseconds}ms');
      return null;
    });
  }

  Future<String?> _probeHosts(List<String> hosts) async {
    if (hosts.isEmpty) return null;
    AppLogger.info(_tag, '本机地址探测: $hosts');
    for (final host in hosts.toSet()) {
      if (await _isValidServer(host)) {
        return host;
      }
    }
    AppLogger.info(_tag, '本机地址探测均失败');
    return null;
  }

  Future<bool> _isValidServer(String host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 250);

    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: serverPort,
        path: '/health',
      );
      final request = await client.getUrl(uri).timeout(
            const Duration(milliseconds: 350),
          );
      final response = await request.close().timeout(
            const Duration(milliseconds: 350),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      final body = await utf8.decodeStream(response);
      final data = jsonDecode(body);
      return data is Map<String, dynamic> && data['msg'] != null;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on HttpException {
      return false;
    } catch (e) {
      AppLogger.warn(_tag, '_isValidServer($host) unexpected error: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
