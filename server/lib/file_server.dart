import 'dart:convert';
import 'dart:io';

const defaultVideoExtensions = ['.webm', '.mp4'];
const defaultRootDir = 'D:/sync/video/output';
const defaultBindHost = '0.0.0.0';
const defaultApiPort = 9090;
const defaultHealthMessage = '服务器正常';

class ServerConfig {
  const ServerConfig({
    this.videoExtensions = defaultVideoExtensions,
    this.rootDir = defaultRootDir,
    this.bindHost = defaultBindHost,
    this.apiPort = defaultApiPort,
    this.healthMessage = defaultHealthMessage,
    this.publicScheme,
    this.publicHost,
    this.publicPort,
  });

  final List<String> videoExtensions;
  final String rootDir;
  final String bindHost;
  final int apiPort;
  final String healthMessage;
  final String? publicScheme;
  final String? publicHost;
  final int? publicPort;

  factory ServerConfig.fromDefines() {
    const rootDir =
        String.fromEnvironment('FILE_SERVER_ROOT_DIR', defaultValue: defaultRootDir);
    const bindHost =
        String.fromEnvironment('FILE_SERVER_BIND_HOST', defaultValue: defaultBindHost);
    const apiPort =
        int.fromEnvironment('FILE_SERVER_API_PORT', defaultValue: defaultApiPort);
    const healthMessage =
        String.fromEnvironment('FILE_SERVER_HEALTH_MSG', defaultValue: defaultHealthMessage);
    const publicSchemeRaw = String.fromEnvironment('FILE_SERVER_PUBLIC_SCHEME');
    const publicHostRaw = String.fromEnvironment('FILE_SERVER_PUBLIC_HOST');
    const publicPortRaw = int.fromEnvironment('FILE_SERVER_PUBLIC_PORT', defaultValue: 0);

    return ServerConfig(
      rootDir: rootDir,
      bindHost: bindHost,
      apiPort: apiPort,
      healthMessage: healthMessage,
      publicScheme: publicSchemeRaw.isEmpty ? null : publicSchemeRaw,
      publicHost: publicHostRaw.isEmpty ? null : publicHostRaw,
      publicPort: publicPortRaw > 0 ? publicPortRaw : null,
    );
  }
}

Future<HttpServer> startFileServer({
  ServerConfig config = const ServerConfig(),
}) async {
  final server = await HttpServer.bind(config.bindHost, config.apiPort);
  server.listen((request) async {
    await handleRequest(request, config: config);
  });
  return server;
}

Future<void> handleRequest(
  HttpRequest request, {
  ServerConfig config = const ServerConfig(),
}) async {
  final response = request.response;

  try {
    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'GET');
      await writeJson(response, {'error': 'Method Not Allowed'});
      return;
    }

    if (request.uri.path == '/' || request.uri.path == '/health') {
      await writeJson(response, {'msg': config.healthMessage});
      return;
    }

    if (request.uri.path == '/video') {
      if (!Directory(config.rootDir).existsSync()) {
        response.statusCode = HttpStatus.internalServerError;
        await writeJson(response, {
          'error': 'root directory not found: ${config.rootDir}',
        });
        return;
      }
      final videoFiles = findVideos(
        config.rootDir,
        videoExtensions: config.videoExtensions,
      );
      final videoUrls = <List<String>>[];

      for (final filePath in videoFiles) {
        final relativePath = toWebPath(filePath, config.rootDir);
        final fileName = filePath.split(Platform.pathSeparator).last;
        final extensionIndex = fileName.lastIndexOf('.');
        final nameWithoutExtension = extensionIndex > 0
            ? fileName.substring(0, extensionIndex)
            : fileName;
        final url = buildPublicFileUrl(relativePath, request, config);
        videoUrls.add([nameWithoutExtension, url]);
      }

      await writeJson(response, videoUrls);
      return;
    }

    final staticFile = resolveStaticFile(request.uri, config.rootDir);
    if (staticFile == null || !staticFile.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      await writeJson(response, {'error': 'Not Found'});
      return;
    }

    await writeFile(request, response, staticFile);
  } catch (error) {
    stderr.writeln('handleRequest error: $error');
    try {
      response.statusCode = HttpStatus.internalServerError;
      await writeJson(response, {'error': 'Internal Server Error'});
    } on Object catch (e, st) {
      stderr.writeln('handleRequest write error after exception: $e\n$st');
      await response.close();
    }
  }
}

List<String> findVideos(
  String directory, {
  List<String> videoExtensions = defaultVideoExtensions,
}) {
  final dir = Directory(directory);
  if (!dir.existsSync()) {
    return [];
  }

  final videos = <String>[];
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final lowerPath = entity.path.toLowerCase();
    if (videoExtensions.any((ext) => lowerPath.endsWith(ext))) {
      videos.add(entity.path);
    }
  }

  return videos;
}

String buildPublicFileUrl(
  String relativePath,
  HttpRequest request,
  ServerConfig config,
) {
  final normalizedPath =
      relativePath.startsWith('/') ? relativePath : '/$relativePath';
  final host = (config.publicHost?.isNotEmpty ?? false)
      ? config.publicHost!
      : request.requestedUri.host;
  final port = (config.publicPort != null && config.publicPort! > 0)
      ? config.publicPort!
      : request.requestedUri.port;
  final scheme = (config.publicScheme?.isNotEmpty ?? false)
      ? config.publicScheme!
      : request.requestedUri.scheme;

  return Uri(
    scheme: scheme,
    host: host,
    port: port,
    path: normalizedPath,
  ).toString();
}

String toWebPath(String filePath, String baseDir) {
  final normalizedFilePath = filePath.replaceAll('\\', '/');
  final normalizedBaseDir = baseDir.replaceAll('\\', '/');
  final prefix = normalizedBaseDir.endsWith('/')
      ? normalizedBaseDir.substring(0, normalizedBaseDir.length - 1)
      : normalizedBaseDir;

  if (!normalizedFilePath.startsWith(prefix)) {
    return normalizedFilePath;
  }

  final relativePath = normalizedFilePath.substring(prefix.length);
  return relativePath.startsWith('/') ? relativePath : '/$relativePath';
}

File? resolveStaticFile(Uri uri, String rootDir) {
  if (uri.path == '/') {
    return null;
  }

  final root = Directory(rootDir).absolute.path;
  final safeSegments = <String>[];
  for (final segment in uri.pathSegments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      return null;
    }
    safeSegments.add(segment);
  }

  const blockedExtensions = [
    '.exe', '.bat', '.cmd', '.ps1', '.sh', '.dll', '.com', '.msi', '.jar',
  ];
  for (final segment in safeSegments) {
    final lower = segment.toLowerCase();
    if (blockedExtensions.any(lower.endsWith)) {
      return null;
    }
  }

  final relativePath = safeSegments.join(Platform.pathSeparator);
  final candidate = File('$root${Platform.pathSeparator}$relativePath');
  final candidatePath = candidate.absolute.path;
  if (!_isWithinRoot(candidatePath, root)) {
    return null;
  }

  return candidate;
}

bool _isWithinRoot(String candidatePath, String rootPath) {
  final normalizedCandidate = candidatePath.replaceAll('\\', '/').toLowerCase();
  final normalizedRoot = rootPath.replaceAll('\\', '/').toLowerCase();
  final prefix =
      normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';
  return normalizedCandidate.startsWith(prefix);
}

Future<void> writeFile(
  HttpRequest request,
  HttpResponse response,
  File file,
) async {
  final fileLength = await file.length();
  response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  response.headers.contentType = _contentTypeFor(file.path);
  final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
  if (rangeHeader != null) {
    final range = _parseByteRange(rangeHeader, fileLength);
    if (range == null) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$fileLength');
      await response.close();
      return;
    }

    response.statusCode = HttpStatus.partialContent;
    response.headers.contentLength = range.length;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes ${range.start}-${range.end}/$fileLength',
    );
    await _safeAddStream(response, file.openRead(range.start, range.end + 1));
    await response.close();
    return;
  }

  response.headers.contentLength = fileLength;
  await _safeAddStream(response, file.openRead());
  await response.close();
}

Future<void> _safeAddStream(HttpResponse response, Stream<List<int>> stream) async {
  try {
    await response.addStream(stream);
  } on Object catch (e, st) {
    stderr.writeln('writeFile stream error: $e\n$st');
  }
}

ByteRange? _parseByteRange(String header, int fileLength) {
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (match == null || fileLength <= 0) {
    return null;
  }

  final startText = match.group(1) ?? '';
  final endText = match.group(2) ?? '';
  if (startText.isEmpty && endText.isEmpty) {
    return null;
  }

  late int start;
  late int end;

  if (startText.isEmpty) {
    final suffixLength = int.tryParse(endText);
    if (suffixLength == null || suffixLength <= 0) {
      return null;
    }
    final safeLength = suffixLength > fileLength ? fileLength : suffixLength;
    start = fileLength - safeLength;
    end = fileLength - 1;
  } else {
    start = int.tryParse(startText) ?? -1;
    if (start < 0 || start >= fileLength) {
      return null;
    }

    if (endText.isEmpty) {
      end = fileLength - 1;
    } else {
      end = int.tryParse(endText) ?? -1;
      if (end < start) {
        return null;
      }
      if (end >= fileLength) {
        end = fileLength - 1;
      }
    }
  }

  return ByteRange(start, end);
}

ContentType _contentTypeFor(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.webm')) {
    return ContentType('video', 'webm');
  }
  if (lowerPath.endsWith('.mp4')) {
    return ContentType('video', 'mp4');
  }
  if (lowerPath.endsWith('.json')) {
    return ContentType.json;
  }
  if (lowerPath.endsWith('.txt')) {
    return ContentType.text;
  }
  return ContentType.binary;
}

Future<void> writeJson(HttpResponse response, Object data) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(data));
  await response.close();
}

class ByteRange {
  const ByteRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;
}
