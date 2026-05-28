import 'dart:io';

import 'package:file_server/file_server.dart';

Future<void> main() async {
  final config = ServerConfig.fromDefines();
  final rootDir = Directory(config.rootDir);
  if (!rootDir.existsSync()) {
    stderr.writeln('Warning: root directory does not exist: ${config.rootDir}');
    stderr.writeln(
      'Hint: use -DFILE_SERVER_ROOT_DIR=D:/your/video/path to point to your video folder.',
    );
  }

  final server = await startFileServer(config: config);
  print('Server running at http://${server.address.host}:${server.port}');
  print('Serving files from ${config.rootDir}');
}
