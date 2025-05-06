import 'package:flutter/material.dart';

import '../main.dart';
import '../models/base_url.dart';
import '../models/video_info.dart';
import '../utils/logger.dart';
import '../utils/tools.dart';

class PlayerTool {
  static final PlayerTool _instance = PlayerTool._internal();
  factory PlayerTool() => _instance;
  PlayerTool._internal();

  static List<VideoInfo> videoList = [];
  List<VideoInfo> overInit = [];
  int nowPage = 0;
  // 实际是load+1个视频
  int load = 5;

  static Future<void> getVideos() async {
    final String loacl = 'http://${BaseUrl.url}:$normalPort';
    List<VideoInfo> list = [];
    try {
      final data = await fetchUrl('$loacl/video');
      data.forEach((videoList) {
        list.add(VideoInfo(title: videoList[0], videoUrl: videoList[1]));
      });
      list.shuffle();
      Log.d('视频列表获取成功:${list.length}');
      videoList = list;
    } catch (e) {
      Log.d('视频列表获取失败：$e');
    }
  }

  Future<void> init(PageController videoPageviewController) async {
    int i = 0;
    for (var video in videoList) {
      bool success = await video.init();
      if (success) {
        overInit.add(video);
      }
      i++;
      if (i == load) break;
    }
    videoPageviewController.addListener(() {
      loadVideos(videoPageviewController);
    });
  }

  Future<void> loadVideos(PageController videoPageviewController) async {
    // 当前页数
    nowPage = videoPageviewController.page!.toInt();
    // 判断下一个页面的内容是否存在
    final coming =
        nowPage + 1 < videoList.length ? videoList[nowPage + 1] : null;
    // 判断这个视频是否已经被预加载过，如果没被加载过，就加载
    if (coming != null && !overInit.contains(coming)) {
      coming.init().then((success) {
        if (success && !overInit.contains(coming)) {
          overInit.add(coming);
        }
      });
    }
    // 如果已经初始化的视频过多，释放先初始化的视频
    if (overInit.length > load) {
      final toRemove = overInit.first;
      toRemove.dispose();
      overInit.remove(toRemove);
    }
  }
}
