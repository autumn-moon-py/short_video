import 'package:get/get.dart' as getx;
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/video_info.dart';
import '../utils/logger.dart';
import '../utils/tools.dart';

Widget sb() => const SizedBox();

class VideoWidget extends StatefulWidget {
  final VideoInfo data;
  const VideoWidget({super.key, required this.data});

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> with WidgetsBindingObserver {
  late VideoInfo data;

  @override
  void initState() {
    data = widget.data;
    init();
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> init() async {
    await data.init();
    data.changeShow(true);
  }

  @override
  void dispose() {
    data.changeShow(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (data.isPlaying.value) data.pause();
    }
    if (state == AppLifecycleState.inactive) {
      if (!data.isPlaying.value) data.play();
    }
  }

  ///长按旋转屏幕
  void onLongPress() {
    var isP = isPortrait();
    if (isP) {
      rotateToLandscape();
    } else {
      rotateToPortrait();
    }
    data.showTitle.value = !data.showTitle.value;
  }

  /// 播放按钮
  Widget playOrPauseB() {
    return Stack(children: [
      GestureDetector(
          onDoubleTap: () => data.playOrPause(),
          onLongPress: () => onLongPress(),
          child: Container(color: Colors.transparent))
    ]);
  }

  /// 视频标题
  Widget titleW() {
    return getx.Obx(() {
      return !data.showTitle.value
          ? sb()
          : SafeArea(
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Text(data.title,
                      style: const TextStyle(color: Colors.white, fontSize: 25))
                ]));
    });
  }

  /// 视频组件
  Widget videoW() {
    return Stack(children: [
      Video(
          controller: data.controller,
          controls: (state) {
            return Stack(children: [
              Container(
                  alignment: Alignment.bottomCenter,
                  child: MaterialPositionIndicator(
                    style: TextStyle(
                      color: Colors.lightBlue,
                    ),
                  )),
              Container(
                  alignment: Alignment.bottomCenter,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  child: MaterialSeekBar()),
            ]);
          })
    ]);
  }

  /// 加载组件
  Widget loadingW() {
    return getx.Obx(() {
      final show = data.showLoading.value;
      return !show
          ? sb()
          : const Center(
              child: SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(color: Colors.white)));
    });
  }

  Widget showPauseIcon() {
    return getx.Obx(() {
      return !data.showPauseIcon.value
          ? sb()
          : const Center(
              child: Icon(Icons.play_circle, color: Colors.white, size: 100));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(color: Colors.black),
      videoW(),
      titleW(),
      loadingW(),
      showPauseIcon(),
      playOrPauseB(),
    ]);
  }
}

class LogPage extends StatelessWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('日志')),
        body: ListView.builder(
            itemCount: Log.logsList.length,
            itemBuilder: (_, index) {
              return ListTile(title: Text(Log.logsList[index]));
            }));
  }
}
