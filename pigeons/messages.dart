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

// --- Text watermark (MVP extension) ---

class TextStyleDto {
  TextStyleDto({
    this.fontFamily = '.SFUI',
    this.fontSizePt = 24.0,
    this.fontWeight = 600,
    this.colorArgb = 0xFFFFFFFF,
  });
  String fontFamily;
  double fontSizePt;
  int fontWeight; // 100..900
  int colorArgb;  // ARGB32
}

class WmStyleDto {
  WmStyleDto({
    this.opacity = 0.6,
    this.stroke = false,
    this.strokeWidth = 1.0,
    this.shadowBlur = 0.0,
  });
  double opacity;     // 0..1
  bool stroke;
  double strokeWidth; // px
  double shadowBlur;  // px
}

class ComposeTextRequest {
  ComposeTextRequest({
    required this.baseImage,
    required this.text,
    this.anchor = Anchor.bottomRight,
    this.margin = 16.0,
    this.marginUnit = Unit.px,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.offsetUnit = Unit.px,
    this.widthPercent = 0.18,
    required this.textStyle,
    required this.style,
    this.format = OutputFormat.jpeg,
    this.quality = 0.9,
  });

  Uint8List baseImage;
  String text;
  Anchor anchor;
  double margin;
  Unit marginUnit;
  double offsetX;
  double offsetY;
  Unit offsetUnit;
  double widthPercent; // if 0, use textStyle.fontSizePt (not used in MVP path)
  TextStyleDto textStyle;
  WmStyleDto style;
  OutputFormat format;
  double quality;
}

@HostApi()
abstract class WatermarkApi {
  @async
  ComposeImageResult composeImage(ComposeImageRequest request);

  // New in text watermark MVP. Implemented later via codegen; keep MethodChannel fallback too.
  @async
  ComposeImageResult composeText(ComposeTextRequest request);
}
