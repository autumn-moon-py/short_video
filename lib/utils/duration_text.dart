String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  String pad(int value) => value.toString().padLeft(2, '0');

  if (hours > 0) {
    return '${pad(hours)}:${pad(minutes)}:${pad(seconds)}';
  }

  return '${pad(minutes)}:${pad(seconds)}';
}
