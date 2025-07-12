import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_protector/screen_protector.dart';

import 'models/base_url.dart';
import 'pages/logic.dart';
import 'pages/page.dart';
import 'video/player_tool.dart';

const normalUrl = "192.168.0.101";
const normalPort = "9090";

Future<void> main() async {
  HttpOverrides.global = DevHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  if (GetPlatform.isAndroid) await ScreenProtector.protectDataLeakageOn();
  await BaseUrl.init();
  await PlayerTool.getVideos();
  Get.put(VideoListLogic());

  runApp(const GetMaterialApp(
      title: '短视频',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: VideoListPage())));
}

class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // 信任所有证书
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
