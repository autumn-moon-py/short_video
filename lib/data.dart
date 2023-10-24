import 'model/video_data.dart';
import 'utils.dart';

class GetVideo {
  static List<VideoData> get(String name, int num) {
    List<VideoData> list = [];
    for (int i = 1; i <= num; i++) {
      final title = '$name($i)';
      final cfUrl = 'https://$cf/$name/$name($i).webm';
      final vercelUrl = 'https://$vercel/proxy/$cf/$name/$name($i).webm';
      final data = VideoData(title: title, cfUrl: cfUrl, vercelUrl: vercelUrl);
      data.localUrl = 'http://$loacl:8000/$name/$name($i).webm';
      data.listen();
      list.add(data);
    }
    list.shuffle();
    return list;
  }
}
