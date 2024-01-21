import 'package:headset_connection_event/headset_event.dart';
import 'package:logger/logger.dart';
import 'package:volume_controller/volume_controller.dart';

import 'video_data.dart';

var logger = Logger();
const loacl = '192.168.16.103';
const videosList = [
  ['A', 94],
  ['B', 35]
];

///视频列表处理
List<VideoInfo> videoGet(List arg) {
  List<VideoInfo> list = [];
  for (var videos in arg) {
    final name = videos[0];
    final num = videos[1];
    for (int i = 1; i <= num; i++) {
      final title = '$name($i)';
      final data = VideoInfo(
          title: title, localUrl: 'http://$loacl:8000/$name/$name($i).webm');
      data.listen();
      list.add(data);
    }
  }
  list.shuffle();
  return list;
}

///耳机插入监听
void getHeadset() {
  HeadsetEvent headsetPlugin = HeadsetEvent();
  var volumeC = VolumeController();
  headsetPlugin.setListener((val) {
    bool isHeadset = val == HeadsetState.CONNECT;
    logger.i('autumn 耳机状态：${isHeadset ? '已插入' : '已拔出'}');
    if (!isHeadset) {
      volumeC.setVolume(0, showSystemUI: false);
      logger.i('autumn 静音');
    } else {
      volumeC.maxVolume(showSystemUI: false);
      logger.i('autumn 恢复音量');
    }
  });
}
