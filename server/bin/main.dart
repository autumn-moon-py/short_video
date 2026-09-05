import 'dart:io';

import 'package:file_server/file_server.dart';

Future<void> main() async {
  final config = ServerConfig.fromDefines();
  final rootDir = Directory(config.rootDir);
  if (!rootDir.existsSync()) {
    stderr.writeln('Error: root directory does not exist: ${config.rootDir}');
    stderr.writeln(
      'Hint: pass -DFILE_SERVER_ROOT_DIR=D:/your/video/path or update 启动.bat',
    );
    exit(2);
  }

  final HttpServer server;
  try {
    server = await startFileServer(config: config);
  } on SocketException catch (e) {
    stderr.writeln('Failed to bind ${config.bindHost}:${config.apiPort} - $e');
    exit(1);
  }

  print('Server running at http://${server.address.host}:${server.port}');
  print('Serving files from ${config.rootDir}');

  ProcessSignal.sigint.watch().listen((_) async {
    print('Shutting down...');
    await server.close(force: false);
    exit(0);
  });
}
