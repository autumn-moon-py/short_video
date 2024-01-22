import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:short_video/video_data.dart';

import '../utils.dart';

class Player {
  List<VideoInfo> videoList = [];
  List<VideoInfo> overInit = [];
  int nowPage = 0;
  int load = 4; //实际是load+1个视频

  Future<void> init(PageController videoPageviewController) async {
    videoList.addAll(videoGet(videosList));
    videoList.shuffle();
    int i = 0;
    //初始预加载
    for (var video in videoList) {
      bool success = await video.init(videoPageviewController);
      if (success) overInit.add(video);
      i++;
      if (i == load) break;
    }
    videoPageviewController.addListener(() {
      loadVideos(videoPageviewController);
    });
  }

  void loadVideos(PageController videoPageviewController) {
    // 当前页数
    nowPage = videoPageviewController.page!.toInt();
    // 判断下一个页面的内容是否存在
    var coming = nowPage + 1 < videoList.length ? videoList[nowPage + 1] : null;
    // 判断这个视频是否已经被预加载过，如果没被加载过，就加载
    if (coming != null && !overInit.contains(coming)) {
      coming.init(videoPageviewController).then((success) {
        if (success && !overInit.contains(coming)) {
          overInit.add(coming);
        }
      });
    }
    // 如果已经初始化的视频过多，释放先初始化的视频
    if (overInit.length > load) {
      var toRemove = overInit.first;
      toRemove.dispose();
      overInit.remove(toRemove);
    }
  }
}

Widget sb({double? width, double? height, Widget? child}) =>
    SizedBox(width: width, height: height, child: child);

class MyVideoPlayer extends StatefulWidget {
  final VideoInfo data;
  const MyVideoPlayer({super.key, required this.data});

  @override
  State<MyVideoPlayer> createState() => _MyVideoPlayerState();
}

class _MyVideoPlayerState extends State<MyVideoPlayer> {
  @override
  void initState() {
    super.initState();
    widget.data.isShow.value = true;
  }

  @override
  void dispose() {
    super.dispose();
    widget.data.isShow.value = false;
  }

  ///长按旋转屏幕
  void onLongPress() {
    var isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    if (isPortrait) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    widget.data.showTitle.value = !widget.data.showTitle.value;
  }

  ///播放按钮
  Widget _tabBox() {
    return !widget.data.isInitialized.value
        ? sb()
        : Stack(children: [
            widget.data.isPlaying.value
                ? sb()
                : const Center(
                    child: Icon(Icons.play_circle,
                        color: Colors.white, size: 100)),
            GestureDetector(
                onDoubleTap: () => widget.data.playOrPause(),
                onLongPress: () => onLongPress(),
                child: Container(color: Colors.transparent))
          ]);
  }

  ///视频标题
  Widget _title() {
    return !widget.data.showTitle.value
        ? sb()
        : Container(
            alignment: Alignment.topCenter,
            margin: const EdgeInsets.only(top: 30),
            child: Text(widget.data.title,
                style: const TextStyle(color: Colors.white, fontSize: 25)));
  }

  ///视频组件
  Widget _video() {
    return Video(
        controller: widget.data.controller,
        fill: Colors.transparent,
        pauseUponEnteringBackgroundMode: false,
        resumeUponEnteringForegroundMode: false,
        controls: (state) => sb());
  }

  ///加载组件
  Widget _loading() {
    return const Center(
        child: SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(color: Colors.white)));
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Stack(children: [
          Container(color: Colors.black),
          _loading(),
          _video(),
          _tabBox(),
          _title(),
        ]));
  }
}
