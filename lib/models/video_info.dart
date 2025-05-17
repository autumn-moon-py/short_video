import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../pages/logic.dart';
import '../utils/logger.dart';
import '../utils/tools.dart';

class VideoInfo {
  String title = '';
  String videoUrl = '';
  String videoPath = "";

  late Player player;
  late VideoController controller;

  var isInited = false.obs;
  var isPlaying = false.obs;
  bool isShow = false;
  var isDispose = false.obs;
  var showTitle = true.obs;
  var showLoading = true.obs;
  var showPauseIcon = false.obs;
  bool liked = false;

  bool startInit = false;

  VideoInfo({required this.title, required this.videoUrl});

  void changeShow(bool value) {
    isShow = value;
    if (isInited.value) {
      value ? play() : pause();
    } else {
      player.stream.buffering.listen((value) {
        if (isShow && value && !isPlaying.value) {
          isInited.value = true;
          Log.d("$title 加载完成,开始播放");
          play();
        }
      });
    }
    showTitle.value = isPortrait();
    Log.d('$title 显示 $value');
  }

  Future<bool> init() async {
    if (isInited.value || startInit) return false;
    startInit = true;
    player = Player();
    controller = VideoController(player);
    listen();
    // final info = await DefaultCacheManager().getFileFromCache(title);
    // if (info != null) {
    //   Log.d("已缓存$title,直接读取");
    //   videoPath = info.file.path;
    // }
    await player.open(Media(videoPath.isEmpty ? videoUrl : videoPath),
        play: false);
    startInit = false;
    isDispose.value = false;
    Log.d("$title 初始化");
    return true;
  }

  Future<void> dispose() async {
    if (isDispose.value) return;
    isInited.value = false;
    isPlaying.value = false;
    isDispose.value = true;
    await player.dispose();
    Log.d('$title 释放');
    if (!liked) return;
    // final info = await DefaultCacheManager().getFileFromCache(title);
    // if (info == null) {
    //   Log.d("未缓存$title,加入缓存");
    //   DefaultCacheManager().downloadFile(videoUrl, key: title);
    // }
  }

  Future<void> play() async {
    if (isPlaying.value) return;
    player.play();
  }

  void pause() {
    if (!isPlaying.value) return;
    player.pause();
    player.seek(Duration.zero);
  }

  void playOrPause() {
    player.playOrPause();
  }

  void listen() {
    player.stream.position.listen((value) {
      if (value.inSeconds > 2 && showLoading.value) {
        showLoading.value = false;
        Log.d('$title 缓冲完成');
      }
    });
    player.stream.playing.listen((value) {
      if (!isInited.value) return;
      isPlaying.value = value;
      Log.d('$title ${value ? "播放" : "暂停"}');
      showPauseIcon.value = !showLoading.value && !value;
    });
    player.stream.completed.listen((value) {
      if (value) {
        Log.d('$title 播放完成');
        liked = true;
        Log.d("标记$title为喜欢,加入缓存队列");
        Get.put(VideoListLogic()).nextPage();
      }
    });
    player.stream.error.listen((error) {
      Log.d("$title error $error");
    });
  }
}

class DurationState {
  const DurationState(
      {required this.progress, required this.buffered, required this.total});
  final Duration progress;
  final Duration buffered;
  final Duration total;
}
