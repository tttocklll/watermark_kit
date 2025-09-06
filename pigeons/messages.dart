// Pigeon schema for watermark_kit (image-only MVP)
// Run: dart run pigeon --input pigeons/messages.dart

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'watermark_kit',
    dartOut: 'lib/gen/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'ios/Classes/Messages.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
class _Cfg {}

enum Anchor { topLeft, topRight, bottomLeft, bottomRight, center }

enum OutputFormat { jpeg, png }
enum Unit { px, percent }

class ComposeImageRequest {
  ComposeImageRequest({
    required this.baseImage,
    required this.watermarkImage,
    this.anchor = Anchor.bottomRight,
    this.margin = 16.0,
    this.widthPercent = 0.18,
    this.opacity = 0.6,
    this.format = OutputFormat.jpeg,
    this.quality = 0.9,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.marginUnit = Unit.px,
    this.offsetUnit = Unit.px,
  });

  Uint8List baseImage;
  Uint8List watermarkImage;
  Anchor anchor;
  double margin;
  double widthPercent;
  double opacity;
  OutputFormat format;
  double quality;
  double offsetX;
  double offsetY;
  Unit marginUnit;
  Unit offsetUnit;
}

class ComposeImageResult {
  ComposeImageResult({
    required this.imageBytes,
    required this.width,
    required this.height,
  });

  Uint8List imageBytes;
  int width;
  int height;
}

@HostApi()
abstract class WatermarkApi {
  @async
  ComposeImageResult composeImage(ComposeImageRequest request);
}
