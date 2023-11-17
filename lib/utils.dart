import 'package:dart_ping/dart_ping.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:logger/logger.dart';

var logger = Logger();
const cf = 'video-cf.subrecovery.top';
const vercel = 'proxy.subrecovery.top';
const loacl = '172.18.30.49';

void toast(String info) {
  EasyLoading.showToast(info);
}

void computeTime(Function func) async {
  DateTime start = DateTime.now();
  await func();
  DateTime end = DateTime.now();
  Duration duration = end.difference(start);
  logger.i('耗时：${duration.inMilliseconds}毫秒');
}

Future<int> pingWeb(String url, String name) async {
  try {
    var response = await Ping(url, count: 1).stream.first;
    final result = response.toMap();
    logger.i('autumn ping-$name: ${result['response']['time']}');
    return result['response']['time'];
  } catch (_) {
    logger.e('autumn ping-$name: error');
    return -1;
  }
}
