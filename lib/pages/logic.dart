import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/video_info.dart';
import '../video/player_tool.dart';

class VideoListLogic extends GetxController {
  final playerT = PlayerTool();
  final videoPageviewController = PageController();

  final videoList = <VideoInfo>[].obs;

  @override
  Future<void> onInit() async {
    videoList.value = PlayerTool.videoList;
    await playerT.init(videoPageviewController);
    super.onInit();
  }

  void nextPage() {
    videoPageviewController.nextPage(
        duration: const Duration(milliseconds: 10), curve: Curves.bounceIn);
  }

  Future<void> onRefresh() async {
    await PlayerTool.getVideos();
    onInit();
  }
}
