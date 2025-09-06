import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_kit/watermark_kit.dart';
import 'package:watermark_kit/watermark_kit_platform_interface.dart';
import 'package:watermark_kit/watermark_kit_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockWatermarkKitPlatform
    with MockPlatformInterfaceMixin
    implements WatermarkKitPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
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
