class VideoItem {
  const VideoItem({
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  factory VideoItem.fromApi(List<dynamic> raw) {
    if (raw.length < 2) {
      throw const FormatException('视频数据格式错误');
    }

    final title = raw[0]?.toString().trim() ?? '';
    final url = raw[1]?.toString().trim() ?? '';
    if (title.isEmpty || url.isEmpty) {
      throw const FormatException('视频标题或地址为空');
    }

    return VideoItem(title: title, url: url);
  }
}
