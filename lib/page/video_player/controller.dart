import 'package:flutter/material.dart';
import 'package:short_video/model/video_data.dart';

import '../../data.dart';

class Player {
  List<VideoData> videoList = [];
  int nowPage = 0;
  int overDispose = 2;
  int load = 2;
  bool canNext = true;

  Future<void> init(
      String which, PageController videoPageviewController) async {
    videoList = GetVideo.get('A', 94);
    int i = 0;
    for (var video in videoList) {
      await video.init(which, videoPageviewController);
      i++;
      if (i == load) break;
    }
    videoPageviewController.addListener(() async {
      nowPage = videoPageviewController.page!.toInt();
      final video = videoList[nowPage];
      await video.init(which, videoPageviewController);
      if (nowPage >= load - 1) {
        for (var i = nowPage; i < nowPage + load; i++) {
          final nVideo = videoList[i];
          await nVideo.init(which, videoPageviewController);
        }
      }
      if (nowPage > overDispose - 1) {
        final disVideo = videoList[nowPage - overDispose];
        await disVideo.dispose();
      }
      // if (!canNext) return;
      // canNext = false;
      // await Future.delayed(const Duration(seconds: 10));
      // videoPageviewController.jumpToPage(nowPage + 1);
      // canNext = true;
    });
  }
}
