import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';

import '../video_data.dart';
import '../utils.dart';
import 'video_player_widget.dart';

class VideoListPage extends StatefulWidget {
  const VideoListPage({super.key});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  final videoPageviewController = PageController();
  final player = Player();
  List<VideoInfo> get videoList => player.videoList;

  @override
  void initState() {
    super.initState();
    ready();
  }

  Future<void> ready() async {
    getHeadset();
    await player.init(videoPageviewController);
    await ScreenProtector.protectDataLeakageOn();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(color: Colors.black),
      PageView.builder(
          itemCount: videoList.length,
          controller: videoPageviewController,
          physics: const BouncingScrollPhysics(),
          scrollDirection: Axis.vertical,
          itemBuilder: (_, index) {
            return MyVideoPlayer(data: videoList[index]);
          }),
    ]);
  }
}
