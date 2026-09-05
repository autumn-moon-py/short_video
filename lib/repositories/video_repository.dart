import 'dart:convert';
import 'dart:io';

import '../models/video_item.dart';
import '../services/server_discovery_service.dart';

class VideoRepository {
  VideoRepository(this._discoveryService);

  final ServerDiscoveryService _discoveryService;

  Future<VideoFeedPayload> fetchVideos() async {
    final endpoint = await _discoveryService.discoverServerHost();
    final uri = Uri(
      scheme: 'http',
      host: endpoint.host,
      port: endpoint.port,
      path: '/video',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);

    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('视频列表请求失败: ${response.statusCode}', uri: uri);
      }

      final body = await utf8.decodeStream(response);
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const FormatException('视频列表返回格式错误');
      }

      final videos = decoded
          .whereType<List<dynamic>>()
          .map(VideoItem.fromApi)
          .toList(growable: false);

      return VideoFeedPayload(serverHost: endpoint.toString(), videos: videos);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> clearCachedServer() {
    return _discoveryService.clearCache();
  }

  Future<bool> hasCachedServer() {
    return _discoveryService.hasCachedServer();
  }
}

class VideoFeedPayload {
  const VideoFeedPayload({
    required this.serverHost,
    required this.videos,
  });

  final String serverHost;
  final List<VideoItem> videos;
}
