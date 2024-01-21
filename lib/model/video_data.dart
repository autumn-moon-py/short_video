import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:short_video/utils.dart';

class VideoData {
  String title = '';
  String localUrl = '';
  late Player player;
  late VideoController controller;
  var isInitialized = false.obs;
  var isPlaying = false.obs;
  var isShow = false.obs;
  var isDispose = false.obs;
  bool showTitle = true;
  bool startInit = false;
  VideoData({required this.title, required this.localUrl});

  void play() {
    if (!isInitialized.value || isPlaying.value) return;
    player.play();
    isPlaying.value = true;
  }

  void pause() {
    if (!isInitialized.value || isDispose.value || !isPlaying.value) return;
    player.pause();
    player.seek(Duration.zero);
    isPlaying.value = false;
  }

  void playOrPause() {
    if (!isInitialized.value || isDispose.value) return;
    player.playOrPause();
    isPlaying.value = !isPlaying.value;
  }

  Future<void> dispose() async {
    if (isDispose.value) return;
    isInitialized.value = false;
    isPlaying.value = false;
    isDispose.value = true;
    await player.dispose();
  }

  Future<bool> init(PageController pageController) async {
    if (isInitialized.value || startInit) return false;
    startInit = true;
    String url = localUrl;
    player = Player();
    controller = VideoController(player);
    await player.open(Media(url), play: false);
    player.stream.error.listen((error) {
      pause();
      logger.i("autumn $title error $error");
      EasyLoading.showError('加载失败\n$error');
    });
    // player.seek(Duration(seconds: player.state.duration.inSeconds - 3));
    try {
      player.stream.completed.listen((value) {
        logger.i('autumn $title isCompleted $value');
        if (value) {
          pause();
          pageController.nextPage(
              duration: const Duration(milliseconds: 10),
              curve: Curves.bounceIn);
        }
      });
    } catch (e) {
      EasyLoading.showError("$e", duration: const Duration(seconds: 10));
    }
    isInitialized.value = true;
    if (isShow.value) play();
    startInit = false;
    return true;
  }

  void listen() {
    isInitialized.listen((value) {
      logger.i('autumn $title isInitialized $value');
    });
    isPlaying.listen((value) {
      logger.i('autumn $title isPlaying $value');
    });
    isShow.listen((value) {
      value ? play() : pause();
      logger.i('autumn $title isShow $value');
    });
    isDispose.listen((value) {
      logger.i('autumn $title isDispose $value');
    });
  }
}
