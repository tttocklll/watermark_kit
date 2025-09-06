
import 'dart:typed_data';
import 'watermark_kit_platform_interface.dart';

class WatermarkKit {
  Future<String?> getPlatformVersion() {
    return WatermarkKitPlatform.instance.getPlatformVersion();
  }

  Future<Uint8List> composeImage({
    required Uint8List inputImage,
    required Uint8List watermarkImage,
    String anchor = 'bottomRight',
    double margin = 16.0,
    double widthPercent = 0.18,
    double opacity = 0.6,
    String format = 'jpeg',
    double quality = 0.9,
  }) {
    return WatermarkKitPlatform.instance.composeImage(
      inputImage: inputImage,
      watermarkImage: watermarkImage,
      anchor: anchor,
      margin: margin,
      widthPercent: widthPercent,
      opacity: opacity,
      format: format,
      quality: quality,
    );
  }
}
