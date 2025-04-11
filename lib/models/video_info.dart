import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
  var isShow = false.obs;
  var isDispose = false.obs;
  var showTitle = true.obs;
  var showLoading = true.obs;
  var showPauseIcon = false.obs;
  bool liked = false;

  bool startInit = false;

  VideoInfo({required this.title, required this.videoUrl});

  void changeShow(bool value) {
    isShow.value = value;
  }

  Future<bool> init() async {
    if (isInited.value || startInit) return false;
    startInit = true;
    player = Player();
    controller = VideoController(player);
    listen();
    final info = await DefaultCacheManager().getFileFromCache(title);
    if (info != null) {
      Log.d("已缓存$title,直接读取");
      videoPath = info.file.path;
    }
    await player.open(Media(videoPath.isEmpty ? videoUrl : videoPath),
        play: false);
    startInit = false;
    return true;
  }

  Future<void> dispose() async {
    if (isDispose.value) return;
    isInited.value = false;
    isPlaying.value = false;
    isDispose.value = true;
    await player.dispose();
    if (!liked) return;
    final info = await DefaultCacheManager().getFileFromCache(title);
    if (info == null) {
      Log.d("未缓存$title,加入缓存");
      await DefaultCacheManager().downloadFile(videoUrl, key: title);
    }
  }

  Future<void> play() async {
    if (isPlaying.value) return;
    player.play();
  }

  void pause() {
    player.pause();
    player.seek(Duration.zero);
  }

  void playOrPause() {
    player.playOrPause();
  }

  void listen() {
    player.stream.position.listen((value) {
      if (value.inSeconds > 1 && showLoading.value) {
        Log.d('$title 加载完成');
        isInited.value = true;
        showLoading.value = false;
      }
      if (value > Duration(seconds: 30) && !liked) {
        liked = true;
        Log.d("标记$title为喜欢,加入缓存队列");
      }
    });
    player.stream.playing.listen((value) {
      isPlaying.value = value;
      showPauseIcon.value = !showLoading.value && !value;
    });
    player.stream.completed.listen((value) {
      if (value) {
        Log.d('$title 播放完成');
        pause();

        Get.put(VideoListLogic()).nextPage();
      }
    });
    player.stream.error.listen((error) {
      // pause();
      Log.d("$title error $error");
    });
    isPlaying.listen((value) {
      Log.d('$title ${value ? "播放" : "暂停"}');
    });
    isShow.listen((value) {
      value ? play() : pause();
      showTitle.value = isPortrait();
      Log.d('$title 显示 $value');
    });
    isDispose.listen((value) {
      Log.d('$title 释放 $value');
    });
  }
}
