import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/base_url.dart';
import 'logic.dart';
import 'widget.dart';

class VideoListPage extends GetView<VideoListLogic> {
  const VideoListPage({super.key});

  Widget refreshB() {
    return Positioned(
        bottom: 0,
        left: 0,
        child: GestureDetector(
            onTap: () => controller.onRefresh(),
            child: Container(
                width: 50,
                height: 50,
                color: Colors.transparent,
                child: const Icon(Icons.refresh, color: Colors.white))));
  }

  Widget changeUrlB() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
          onTap: () {
            Get.defaultDialog(
                title: "修改地址",
                content: TextField(onSubmitted: (value) {
                  BaseUrl.save(value);
                  Get.back();
                }));
          },
          child: Container(
              width: 50,
              height: 50,
              color: Colors.transparent,
              child: const Icon(Icons.settings, color: Colors.white))),
    );
  }

  Widget logB() {
    return Positioned(
        bottom: 0,
        right: 0,
        child: GestureDetector(
            onTap: () => Get.to(() => const LogPage()),
            child: Container(
                width: 50,
                height: 50,
                color: Colors.transparent,
                child: const Icon(Icons.list, color: Colors.white))));
  }

  Widget videoPageview() {
    return Obx(() {
      if (controller.videoList.isEmpty) {
        return const Center(
            child: Text("视频列表为空", style: TextStyle(color: Colors.white)));
      }
      return PageView.builder(
          itemCount: controller.videoList.length,
          controller: controller.videoPageviewController,
          physics: const BouncingScrollPhysics(),
          scrollDirection: Axis.vertical,
          itemBuilder: (_, index) {
            return VideoWidget(data: controller.videoList[index]);
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(color: Colors.black),
      logB(),
      refreshB(),
      changeUrlB(),
      videoPageview()
    ]);
  }
}
