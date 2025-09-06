
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
    double offsetX = 0.0,
    double offsetY = 0.0,
    String marginUnit = 'px',
    String offsetUnit = 'px',
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
      offsetX: offsetX,
      offsetY: offsetY,
      marginUnit: marginUnit,
      offsetUnit: offsetUnit,
    );
  }

  Future<Uint8List> composeTextImage({
    required Uint8List inputImage,
    required String text,
    String anchor = 'bottomRight',
    double margin = 16.0,
    String marginUnit = 'px',
    double offsetX = 0.0,
    double offsetY = 0.0,
    String offsetUnit = 'px',
    double widthPercent = 0.18,
    double opacity = 0.6,
    String format = 'jpeg',
    double quality = 0.9,
    String fontFamily = '.SFUI',
    double fontSizePt = 24.0,
    int fontWeight = 600,
    int colorArgb = 0xFFFFFFFF,
  }) {
    return WatermarkKitPlatform.instance.composeTextImage(
      inputImage: inputImage,
      text: text,
      anchor: anchor,
      margin: margin,
      marginUnit: marginUnit,
      offsetX: offsetX,
      offsetY: offsetY,
      offsetUnit: offsetUnit,
      widthPercent: widthPercent,
      opacity: opacity,
      format: format,
      quality: quality,
      fontFamily: fontFamily,
      fontSizePt: fontSizePt,
      fontWeight: fontWeight,
      colorArgb: colorArgb,
    );
  }
}
