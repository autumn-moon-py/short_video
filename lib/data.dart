import 'model/video_data.dart';

const loacl = '192.168.16.103';

class GetVideo {
  static List<VideoData> get(String name, int num, [String format = "webm"]) {
    List<VideoData> list = [];
    for (int i = 1; i <= num; i++) {
      final title = '$name($i)';
      final data = VideoData(
          title: title, localUrl: 'http://$loacl:8000/$name/$name($i).$format');
      data.listen();
      list.add(data);
    }
    list.shuffle();
    return list;
  }
}
