import 'package:flutter/material.dart';
import 'package:short_video/model/video_data.dart';

import '../../data.dart';

class Player {
  List<VideoData> videoList = [];
  List<VideoData> overInit = [];
  List<VideoData> waitDispose = [];
  int nowPage = 0;
  int load = 4;

  Future<void> init(PageController videoPageviewController) async {
    videoList.addAll(GetVideo.get('A', 94));
    videoList.addAll(GetVideo.get('B', 35));
    int i = 0;
    //初始预加载load个
    for (var video in videoList) {
      bool success = await video.init(videoPageviewController);
      if (success) overInit.add(video);
      i++;
      if (i == load) break;
    }
    videoPageviewController.addListener(() async {
      nowPage = videoPageviewController.page!.toInt();
      if (overInit.length > 4) {
        waitDispose.add(overInit[0]);
        overInit.removeAt(0);
      }
      //如果当前视频没有预加载/已释放再调用加载
      final video = videoList[nowPage];
      bool success = await video.init(videoPageviewController);
      if (success) overInit.add(video);
    });
  }
}
