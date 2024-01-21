import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:headset_connection_event/headset_event.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:short_video/model/video_data.dart';
import 'package:short_video/page/video_player/controller.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../utils.dart';

class VideoController extends GetxController {
  VideoController();
  var isHeadset = false.obs;
  var volumeC = VolumeController();
  final videoPageviewController = PageController();
  final player = Player();
  int get videoListLength => player.videoList.length;
  List<VideoData> get videoList => player.videoList;

  _initData() async {
    // getHeadset();
    await ScreenProtector.protectDataLeakageOn();
    player.init(videoPageviewController);
    update(["video"]);
  }

  @override
  void onReady() {
    super.onReady();
    _initData();
  }

  void getHeadset() {
    HeadsetEvent headsetPlugin = HeadsetEvent();
    headsetPlugin.setListener((val) {
      isHeadset.value = val == HeadsetState.CONNECT;
      logger.i('autumn 耳机状态：${isHeadset.value ? '已插入' : '已拔出'}');
      if (!isHeadset.value) {
        volumeC.setVolume(0, showSystemUI: false);
        logger.i('autumn 静音');
      } else {
        volumeC.maxVolume(showSystemUI: false);
        logger.i('autumn 恢复音量');
      }
    });
  }
}
