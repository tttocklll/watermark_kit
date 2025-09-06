import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:watermark_kit/watermark_kit.dart';
import 'package:watermark_kit/watermark_kit_platform_interface.dart';
import 'package:watermark_kit/watermark_kit_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockWatermarkKitPlatform
    with MockPlatformInterfaceMixin
    implements WatermarkKitPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<Uint8List> composeImage({required Uint8List inputImage, required Uint8List watermarkImage, String anchor = 'bottomRight', double margin = 16.0, double widthPercent = 0.18, double opacity = 0.6, String format = 'jpeg', double quality = 0.9, double offsetX = 0.0, double offsetY = 0.0, String marginUnit = 'px', String offsetUnit = 'px'}) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> composeTextImage({required Uint8List inputImage, required String text, String anchor = 'bottomRight', double margin = 16.0, String marginUnit = 'px', double offsetX = 0.0, double offsetY = 0.0, String offsetUnit = 'px', double widthPercent = 0.18, double opacity = 0.6, String format = 'jpeg', double quality = 0.9, String fontFamily = '.SFUI', double fontSizePt = 24.0, int fontWeight = 600, int colorArgb = 0xFFFFFFFF}) {
    throw UnimplementedError();
  }

  @override
  Future<VideoTask> composeVideo({required String inputVideoPath, String? outputVideoPath, Uint8List? watermarkImage, String? text, String anchor = 'bottomRight', double margin = 16.0, String marginUnit = 'px', double offsetX = 0.0, double offsetY = 0.0, String offsetUnit = 'px', double widthPercent = 0.18, double opacity = 0.6, String codec = 'h264', int? bitrateBps, double? maxFps, int? maxLongSide}) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelVideo(String taskId) {
    throw UnimplementedError();
  }
}

void main() {
  final WatermarkKitPlatform initialPlatform = WatermarkKitPlatform.instance;

  test('$MethodChannelWatermarkKit is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelWatermarkKit>());
  });

  test('getPlatformVersion', () async {
    WatermarkKit watermarkKitPlugin = WatermarkKit();
    MockWatermarkKitPlatform fakePlatform = MockWatermarkKitPlatform();
    WatermarkKitPlatform.instance = fakePlatform;

    expect(await watermarkKitPlugin.getPlatformVersion(), '42');
  });
}
