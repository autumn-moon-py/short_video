import 'package:flutter/material.dart';

class Log {
  static final Log _instance = Log._internal();
  Log._internal();
  factory Log() => _instance;

  static List<String> logsList = [];
  static void d(String text) {
    logsList.add(text);
    debugPrint("秋月 $text");
  }
}
