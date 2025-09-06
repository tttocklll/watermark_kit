import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'watermark_kit_platform_interface.dart';
import 'dart:typed_data';

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

  @override
  Future<Uint8List> composeImage({
    required Uint8List inputImage,
    required Uint8List watermarkImage,
    String anchor = 'bottomRight',
    double margin = 16.0,
    double widthPercent = 0.18,
    double opacity = 0.6,
    String format = 'jpeg',
    double quality = 0.9,
  }) async {
    final args = <String, dynamic>{
      'inputImage': inputImage,
      'watermarkImage': watermarkImage,
      'anchor': anchor,
      'margin': margin,
      'widthPercent': widthPercent,
      'opacity': opacity,
      'format': format,
      'quality': quality,
    };
    final bytes = await methodChannel.invokeMethod<Uint8List>('composeImage', args);
    if (bytes == null) {
      throw PlatformException(code: 'compose_failed', message: 'No bytes returned');
    }
    return bytes;
  }
}
