import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
  int quadrant = 0;

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

  ///触摸区域检测
  void onPanDown(DragDownDetails details) {
    double dx = 0;
    double dy = 0;
    List<double> origin = [0.5.sw, 0.5.sh];
    List<double> onTap = [0, 0];
    dx = details.globalPosition.dx;
    dy = details.globalPosition.dy;
    onTap[0] = dx - origin[0];
    onTap[1] = dy - origin[1];
    if (onTap[0] > 0) {
      if (onTap[1] > 0) {
        quadrant = 4;
      }
      if (onTap[1] < 0) {
        quadrant = 1;
      }
    }
    if (onTap[0] < 0) {
      if (onTap[1] > 0) {
        quadrant = 3;
      }
      if (onTap[1] < 0) {
        quadrant = 2;
      }
    }
  }

  ///屏幕旋转
  void onLongPress() {
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      if (quadrant == 1 || quadrant == 4) {
        widget.data.showTitle = false;
        SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeRight]);
      } else {
        widget.data.showTitle = false;
        SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeLeft]);
      }
    } else {
      widget.data.showTitle = true;
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    setState(() {});
  }

  ///播放按钮
  Widget _tabBox() {
    return !widget.data.isInitialized.value && !widget.data.isShow.value
        ? sb()
        : Stack(children: [
            widget.data.isPlaying.value
                ? sb()
                : const Center(
                    child: Icon(Icons.play_circle,
                        color: Colors.white, size: 100)),
            GestureDetector(
                onDoubleTap: () => widget.data.playOrPause(),
                onPanDown: onPanDown,
                onLongPress: onLongPress,
                child: Container(color: Colors.transparent))
          ]);
  }

  ///视频标题
  Widget _title() {
    return !widget.data.showTitle
        ? sb()
        : Container(
            alignment: Alignment.topCenter,
            margin: const EdgeInsets.only(top: 30),
            child: Text(widget.data.title,
                style: const TextStyle(color: Colors.white, fontSize: 25)));
  }

  ///视频组件
  Widget _video() {
    return Center(
        child: !widget.data.isInitialized.value
            ? const CircularProgressIndicator()
            : SizedBox(
                width: 1.sw,
                child: Video(
                    controller: widget.data.controller,
                    wakelock: false,
                    pauseUponEnteringBackgroundMode: false,
                    resumeUponEnteringForegroundMode: false,
                    controls: (state) => sb())));
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Stack(children: [
          Container(color: Colors.black),
          _video(),
          _tabBox(),
          _title()
        ]));
  }
}
