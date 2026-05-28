import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class ServerDiscoveryService {
  static const int serverPort = 9090;
  static const String _cachedHostKey = 'cached_server_host';
  static const String _definedHostKey = 'VIDEO_SERVER_HOST';
  static const Duration _scanTimeout = Duration(seconds: 5);

  Future<String> discoverServerHost() async {
    final prefs = await SharedPreferences.getInstance();
    final definedHost = normalizeDefinedHost(
      const String.fromEnvironment(_definedHostKey),
    );
    final cachedHost = prefs.getString(_cachedHostKey);

    if (definedHost != null) {
      if (await _isValidServer(definedHost)) {
        await prefs.setString(_cachedHostKey, definedHost);
        return definedHost;
      }

      throw SocketException('指定服务地址不可用: $definedHost');
    }

    if (cachedHost != null && await _isValidServer(cachedHost)) {
      return cachedHost;
    }

    final directHost = await _probeHosts(
      buildDirectHostCandidates(isDesktop: _isDesktopPlatform),
    );
    if (directHost != null) {
      await prefs.setString(_cachedHostKey, directHost);
      return directHost;
    }

    final subnetPrefix = await _readSubnetPrefix();
    if (subnetPrefix == null) {
      throw const SocketException('未识别到可扫描的局域网 IPv4 地址');
    }

    final host = await _scanSubnet(subnetPrefix);
    if (host == null) {
      throw const SocketException('5 秒内未找到可用的视频服务');
    }

    await prefs.setString(_cachedHostKey, host);
    return host;
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedHostKey);
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

    Future<void> worker() async {
      activeWorkers++;
      try {
        while (!completer.isCompleted &&
            stopwatch.elapsed < _scanTimeout &&
            nextHost <= 254) {
          final host = '$subnetPrefix.${nextHost++}';
          if (await _isValidServer(host)) {
            if (!completer.isCompleted) {
              completer.complete(host);
            }
            return;
          }
        }
      } finally {
        activeWorkers--;
        if (activeWorkers == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }
    }

    for (var i = 0; i < concurrency && i < 254; i++) {
      unawaited(worker());
    }

    return completer.future.timeout(_scanTimeout, onTimeout: () => null);
  }

  Future<String?> _probeHosts(List<String> hosts) async {
    for (final host in hosts.toSet()) {
      if (await _isValidServer(host)) {
        return host;
      }
    }

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
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
