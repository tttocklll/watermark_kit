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
    throw UnimplementedError('composeImage() has not been implemented.');
  }
}
