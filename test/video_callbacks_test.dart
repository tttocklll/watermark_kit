import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_kit/gen/messages.g.dart' as pigeon;
import 'package:watermark_kit/watermark_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('composeVideo routes progress and completion via callbacks', () async {
    final codec = pigeon.WatermarkCallbacks.pigeonChannelCodec;

    // Mock host handler for composeVideo to echo back a completion later.
    const composeVideoChannel = 'dev.flutter.pigeon.watermark_kit.WatermarkApi.composeVideo';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(composeVideoChannel, (ByteData? message) async {
      final List<Object?>? args = codec.decodeMessage(message) as List<Object?>?;
      final req = args![0] as pigeon.ComposeVideoRequest;

      // Simulate host sending progress callbacks before completing.
      Future.delayed(const Duration(milliseconds: 10), () async {
        // onVideoProgress
        final chan = const BasicMessageChannel<Object?>(
            'dev.flutter.pigeon.watermark_kit.WatermarkCallbacks.onVideoProgress',
            StandardMessageCodec());
        // Use the codec used by pigeon (same as WatermarkApi's codec).
        final ByteData msg1 = codec.encodeMessage(<Object?>[req.taskId!, 0.5, 1.0])!;
        // Dispatch to the channel handler
        // ignore: invalid_use_of_protected_member
        ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          chan.name,
          msg1,
          (ByteData? _) {},
        );

        // onVideoCompleted
        final completedChan = const BasicMessageChannel<Object?>(
            'dev.flutter.pigeon.watermark_kit.WatermarkCallbacks.onVideoCompleted',
            StandardMessageCodec());
        final res = pigeon.ComposeVideoResult(
          taskId: req.taskId!,
          outputVideoPath: '/tmp/out.mp4',
          width: 1280,
          height: 720,
          durationMs: 1000,
          codec: pigeon.VideoCodec.h264,
        );
        final ByteData msg2 = codec.encodeMessage(<Object?>[res])!;
        // ignore: invalid_use_of_protected_member
        ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          completedChan.name,
          msg2,
          (ByteData? _) {},
        );
      });

      // Return eventual ComposeVideoResult (same as completion callback)
      final ret = pigeon.ComposeVideoResult(
        taskId: req.taskId!,
        outputVideoPath: '/tmp/out.mp4',
        width: 1280,
        height: 720,
        durationMs: 1000,
        codec: pigeon.VideoCodec.h264,
      );
      return codec.encodeMessage(<Object?>[ret]);
    });

    final wm = WatermarkKit();
    final task = await wm.composeVideo(
      inputVideoPath: '/tmp/in.mp4',
      text: 'hello',
    );
    final sub = task.progress.listen((_) {});
    final res = await task.done.timeout(const Duration(seconds: 1));
    await sub.cancel();
    expect(res.path, '/tmp/out.mp4');
    expect(res.width, 1280);
    expect(res.codec, 'h264');
  });
}
