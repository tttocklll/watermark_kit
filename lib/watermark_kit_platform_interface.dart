import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'watermark_kit_method_channel.dart';

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
}
