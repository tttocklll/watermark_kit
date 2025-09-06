
import 'watermark_kit_platform_interface.dart';

class WatermarkKit {
  Future<String?> getPlatformVersion() {
    return WatermarkKitPlatform.instance.getPlatformVersion();
  }
}
