import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'page/video/controller.dart';
import 'page/video/view.dart';

class MyBingding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => VideoController());
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemUiOverlayStyle systemUiOverlayStyle =
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent);
  SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
        designSize: const Size(1080, 2412),
        builder: (context, child) {
          return GetMaterialApp(
              title: '短视频',
              initialBinding: MyBingding(),
              debugShowCheckedModeBanner: false,
              builder: EasyLoading.init(),
              home: Scaffold(body: child));
        },
        child: const VideoListPage());
  }
}

class VideoListPage extends StatefulWidget {
  const VideoListPage({super.key});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  @override
  Widget build(BuildContext context) {
    return const VideoPage();
  }
}
