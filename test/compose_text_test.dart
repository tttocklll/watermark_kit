import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_kit/gen/messages.g.dart' as pigeon;
import 'package:watermark_kit/watermark_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('composeTextImage', () {
    const pigeonChannelName =
        'dev.flutter.pigeon.watermark_kit.WatermarkApi.composeText';

    tearDown(() async {
      // Clean up any mock handlers.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(pigeonChannelName, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('watermark_kit'),
        null,
      );
    });

    test('uses Pigeon channel when available', () async {
      final codec = pigeon.WatermarkApi.pigeonChannelCodec;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(pigeonChannelName, (ByteData? message) async {
        final List<Object?>? args = codec.decodeMessage(message) as List<Object?>?;
        expect(args, isNotNull);
        final req = args![0] as pigeon.ComposeTextRequest;
        expect(req.text, 'hello');
        expect(req.anchor, pigeon.Anchor.bottomRight);
        expect(req.margin, 16.0);
        expect(req.marginUnit, pigeon.Unit.px);
        expect(req.widthPercent, closeTo(0.18, 1e-9));
        // Return a small valid response
        final res = pigeon.ComposeImageResult(
          imageBytes: Uint8List.fromList(const [1, 2, 3]),
          width: 10,
          height: 10,
        );
        return codec.encodeMessage(<Object?>[res]);
      });

      final wm = WatermarkKit();
      final out = await wm.composeTextImage(
        inputImage: Uint8List.fromList(const [9, 9, 9]),
        text: 'hello',
      );
      expect(out, equals(Uint8List.fromList(const [1, 2, 3])));
    });

    test('falls back to MethodChannel composeText when Pigeon unavailable', () async {
      // No Pigeon handler registered -> PlatformException thrown inside client.
      // Set up legacy MethodChannel handler.
      final chan = const MethodChannel('watermark_kit');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(chan, (MethodCall call) async {
        expect(call.method, 'composeText');
        final args = call.arguments as Map<Object?, Object?>;
        expect(args['text'], 'world');
        expect(args['anchor'], 'topLeft');
        expect(args['format'], 'png');
        return Uint8List.fromList(const [4, 5, 6]);
      });

      final wm = WatermarkKit();
      final out = await wm.composeTextImage(
        inputImage: Uint8List.fromList(const [7, 7, 7]),
        text: 'world',
        anchor: 'topLeft',
        format: 'png',
      );
      expect(out, equals(Uint8List.fromList(const [4, 5, 6])));
    });
  });
}
