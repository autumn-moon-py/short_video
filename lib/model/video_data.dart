import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:short_video/utils.dart';
// import 'package:video_player/video_player.dart';

class VideoData {
  String title = '';
  String cfUrl = '';
  String vercelUrl = '';
  String localUrl = '';
  // late VideoPlayerController controller;
  late Player player;
  late VideoController controller;
  var isInitialized = false.obs;
  var isPlaying = false.obs;
  var isShow = false.obs;
  var isDispose = false.obs;
  bool showTitle = true;
  bool startInit = false;
  VideoData(
      {required this.title, required this.cfUrl, required this.vercelUrl});

  void play() {
    if (!isInitialized.value || isPlaying.value) return;
    // controller.play();
    player.play();
    isPlaying.value = true;
  }

  void pause() {
    if (!isInitialized.value || isDispose.value || !isPlaying.value) return;
    // controller.pause();
    player.pause();
    player.seek(Duration.zero);
    isPlaying.value = false;
  }

  void playOrPause() {
    if (!isInitialized.value || isDispose.value) return;
    // isPlaying.value ? controller.pause() : controller.play();
    player.playOrPause();
    isPlaying.value = !isPlaying.value;
  }

  Future<void> dispose() async {
    // controller.dispose();
    if (isDispose.value) return;
    isInitialized.value = false;
    isPlaying.value = false;
    isDispose.value = true;
    await player.dispose();
  }

  Future<void> init(String which) async {
    if (isInitialized.value || startInit) return;
    startInit = true;
    // DateTime start = DateTime.now();
    // mdeia_kit
    String url = '';
    if (which == 'local') {
      url = localUrl;
    } else if (which == 'vercel') {
      url = vercelUrl;
    } else {
      url = cfUrl;
    }
    player = Player();
    controller = VideoController(player);
    await player.open(Media(url), play: false);
    // video_player
    // controller = VideoPlayerController.networkUrl(Uri.parse(vercelUrl));
    // await controller.initialize();
    isInitialized.value = true;
    if (isShow.value) play();
    startInit = false;
    // DateTime end = DateTime.now();
    // Duration duration = end.difference(start);
    // logger.i('autumn $title time: ${duration.inSeconds}s');
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
