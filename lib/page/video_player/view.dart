import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:short_video/model/video_data.dart';

import '../../widget.dart';

class MyVideoPlayer extends StatefulWidget {
  final VideoData data;
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
                onPanDown: onPanDown,
                onLongPress: onLongPress,
                child: Container(color: Colors.transparent))
          ]);
  }

  Widget _title() {
    return !widget.data.isInitialized.value || !widget.data.showTitle
        ? sb()
        : Container(
            alignment: Alignment.topCenter,
            margin: const EdgeInsets.only(top: 30),
            child: Text(widget.data.title,
                style: const TextStyle(color: Colors.white, fontSize: 25)));
  }

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
