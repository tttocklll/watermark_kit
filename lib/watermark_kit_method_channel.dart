import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'watermark_kit_platform_interface.dart';

/// An implementation of [WatermarkKitPlatform] that uses method channels.
class MethodChannelWatermarkKit extends WatermarkKitPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('watermark_kit');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
