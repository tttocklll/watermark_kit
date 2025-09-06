import 'dart:async';

class VideoResult {
  final String path;
  final int width;
  final int height;
  final int durationMs;
  final String codec;
  const VideoResult({
    required this.path,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.codec,
  });
}

class VideoTask {
  final String taskId;
  final Stream<double> progress;
  final Future<VideoResult> done;
  final Future<void> Function() cancel;
  const VideoTask({
    required this.taskId,
    required this.progress,
    required this.done,
    required this.cancel,
  });
}
