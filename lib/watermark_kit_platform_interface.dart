import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'watermark_kit_method_channel.dart';
import 'dart:typed_data';

abstract class WatermarkKitPlatform extends PlatformInterface {
  /// Constructs a WatermarkKitPlatform.
  WatermarkKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static WatermarkKitPlatform _instance = MethodChannelWatermarkKit();

  /// The default instance of [WatermarkKitPlatform] to use.
  ///
  /// Defaults to [MethodChannelWatermarkKit].
  static WatermarkKitPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [WatermarkKitPlatform] when
  /// they register themselves.
  static set instance(WatermarkKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Composes [inputImage] with [watermarkImage] and returns encoded bytes.
  ///
  /// Options (all optional with defaults):
  /// - anchor: one of 'topLeft','topRight','bottomLeft','bottomRight','center' (default: 'bottomRight')
  /// - margin: logical pixels in output space (default: 16.0)
  /// - widthPercent: 0..1 relative to base width (default: 0.18)
  /// - opacity: 0..1 applied to watermark (default: 0.6)
  /// - format: 'jpeg' | 'png' (default: 'jpeg')
  /// - quality: 0..1 for JPEG (default: 0.9)
  /// - offsetX/offsetY: offsets from the anchor (default: 0)
  /// - marginUnit: 'px' | 'percent' (default: 'px')
  /// - offsetUnit: 'px' | 'percent' (default: 'px')
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
    throw UnimplementedError('composeImage() has not been implemented.');
  }

  /// Composes [inputImage] with a text watermark and returns encoded bytes.
  ///
  /// Options (defaults mirror composeImage where applicable):
  /// - text: watermark text (required)
  /// - anchor: 'topLeft'|'topRight'|'bottomLeft'|'bottomRight'|'center' (default: 'bottomRight')
  /// - margin: logical px (default: 16.0) with [marginUnit] 'px'|'percent'
  /// - offsetX/offsetY: offsets with [offsetUnit] 'px'|'percent' (default: 0)
  /// - widthPercent: 0..1 of base width to fit text (default: 0.18)
  /// - opacity: 0..1 applied post‑raster (default: 0.6)
  /// - format: 'jpeg' | 'png' (default: 'jpeg'), JPEG [quality] 0..1
  /// - fontFamily: default '.SFUI'
  /// - fontSizePt: default 24.0
  /// - fontWeight: 100..900 (default 600)
  /// - colorArgb: ARGB32 integer (default 0xFFFFFFFF)
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
    throw UnimplementedError('composeTextImage() has not been implemented.');
  }
}
