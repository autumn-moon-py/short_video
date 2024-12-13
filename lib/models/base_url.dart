import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../utils/logger.dart';

class BaseUrl {
  static final BaseUrl _instance = BaseUrl._internal();
  BaseUrl._internal();
  factory BaseUrl() => _instance;

  static String url = "";

  static String saveKey = 'baseUrl';
  static late SharedPreferences sp;

  static Future<void> init() async {
    sp = await SharedPreferences.getInstance();
    load();
  }

  static void load() {
    url = sp.getString(saveKey) ?? normalUrl;
    Log.d("当前地址 $url");
  }

  static void save(String newUrl) {
    url = newUrl;
    sp.setString(saveKey, newUrl);
    Log.d("保存新地址 $newUrl");
  }
}
