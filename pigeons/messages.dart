// Pigeon schema for watermark_kit (image + video MVP)
// Run: dart run pigeon --input pigeons/messages.dart

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'watermark_kit',
    dartOut: 'lib/gen/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'ios/Classes/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    kotlinOut: 'android/src/main/kotlin/com/tttocklll/watermark_kit/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.tttocklll.watermark_kit',
    ),
  ),
)
enum Anchor { topLeft, topRight, bottomLeft, bottomRight, center }

enum OutputFormat { jpeg, png }
enum MeasureUnit { px, percent }

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
    this.marginUnit = MeasureUnit.px,
    this.offsetUnit = MeasureUnit.px,
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
  MeasureUnit marginUnit;
  MeasureUnit offsetUnit;
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
    this.marginUnit = MeasureUnit.px,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.offsetUnit = MeasureUnit.px,
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
  MeasureUnit marginUnit;
  double offsetX;
  double offsetY;
  MeasureUnit offsetUnit;
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

  // --- Video watermark (iOS MVP) ---
  @async
  ComposeVideoResult composeVideo(ComposeVideoRequest request);

  void cancel(String taskId);
}

// --- Host -> Flutter callbacks for long-running video tasks ---
@FlutterApi()
abstract class WatermarkCallbacks {
  void onVideoProgress(String taskId, double progress, double etaSec);
  void onVideoCompleted(ComposeVideoResult result);
  void onVideoError(String taskId, String code, String message);
}

// --- Video types ---
enum VideoCodec { h264, hevc }

class ComposeVideoRequest {
  ComposeVideoRequest({
    this.taskId,
    required this.inputVideoPath,
    this.outputVideoPath,
    this.watermarkImage,
    this.text,
    this.anchor = Anchor.bottomRight,
    this.margin = 16.0,
    this.marginUnit = MeasureUnit.px,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.offsetUnit = MeasureUnit.px,
    this.widthPercent = 0.18,
    this.opacity = 0.6,
    this.codec = VideoCodec.h264,
    this.bitrateBps,
    this.maxFps,
    this.maxLongSide,
  });

  String? taskId; // If null, host side will generate one
  String inputVideoPath;
  String? outputVideoPath;
  Uint8List? watermarkImage; // If null and text!=null, text watermark is used
  String? text;              // If non-null, render text -> image internally
  Anchor anchor;
  double margin;
  MeasureUnit marginUnit;
  double offsetX;
  double offsetY;
  MeasureUnit offsetUnit;
  double widthPercent;
  double opacity;
  VideoCodec codec;
  int? bitrateBps;
  double? maxFps;
  int? maxLongSide;
}

class ComposeVideoResult {
  ComposeVideoResult({
    required this.taskId,
    required this.outputVideoPath,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.codec,
  });

  String taskId;
  String outputVideoPath;
  int width;
  int height;
  int durationMs;
  VideoCodec codec;
}
