import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../video_player/view.dart';
import 'controller.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({Key? key}) : super(key: key);

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _VideoViewGetX();
  }
}

class _VideoViewGetX extends GetView<VideoController> {
  _VideoViewGetX({Key? key}) : super(key: key);
  @override
  final controller = Get.find<VideoController>();

  Widget _videoPageView() {
    return Stack(children: [
      Container(color: Colors.black),
      PageView.builder(
          itemCount: controller.videoList.length,
          controller: controller.videoPageviewController,
          physics: const BouncingScrollPhysics(),
          scrollDirection: Axis.vertical,
          itemBuilder: (_, index) {
            return MyVideoPlayer(data: controller.videoList[index]);
          })
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoController>(
        init: VideoController(),
        id: "video",
        builder: (_) {
          return _videoPageView();
        });
  }
}
