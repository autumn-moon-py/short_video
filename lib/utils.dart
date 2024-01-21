import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:logger/logger.dart';

var logger = Logger();

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
