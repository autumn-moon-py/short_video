import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/feed_controller.dart';
import 'pages/feed_page.dart';
import 'repositories/video_repository.dart';
import 'services/server_discovery_service.dart';

class ShortVideoApp extends StatelessWidget {
  const ShortVideoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '短视频',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6A3D),
          secondary: Color(0xFFFFA25B),
          surface: Color(0xFF101010),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFFFF6A3D),
          inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
          thumbColor: const Color(0xFFFFA25B),
          overlayColor: const Color(0x33FF6A3D),
          trackHeight: 3,
        ),
      ),
      initialBinding: BindingsBuilder(() {
        Get.put(ServerDiscoveryService());
        Get.put(VideoRepository(Get.find<ServerDiscoveryService>()));
        Get.put(FeedController(Get.find<VideoRepository>()));
      }),
      home: const FeedPage(),
    );
  }
}
