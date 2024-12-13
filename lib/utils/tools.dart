import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 判断竖屏
bool isPortrait() {
  return MediaQuery.of(Get.context!).orientation == Orientation.portrait;
}

/// 旋转为竖屏
Future<void> rotateToPortrait() async {
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

/// 旋转为横屏
Future<void> rotateToLandscape() async {
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
}

Future fetchUrl(String url) async {
  final httpClient = HttpClient();
  final uri = Uri.parse(url);
  final request = await httpClient.getUrl(uri);
  final response = await request.close();
  var jsonResponse = await response.transform(utf8.decoder).join();
  final data = jsonDecode(jsonResponse);
  return data;
}
