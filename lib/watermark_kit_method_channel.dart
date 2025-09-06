import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gen/messages.g.dart' as pigeon;
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
    pigeon.Anchor _anchorFromString(String s) {
      switch (s) {
        case 'topLeft':
          return pigeon.Anchor.topLeft;
        case 'topRight':
          return pigeon.Anchor.topRight;
        case 'bottomLeft':
          return pigeon.Anchor.bottomLeft;
        case 'center':
          return pigeon.Anchor.center;
        case 'bottomRight':
        default:
          return pigeon.Anchor.bottomRight;
      }
    }

    pigeon.OutputFormat _formatFromString(String s) {
      switch (s) {
        case 'png':
          return pigeon.OutputFormat.png;
        case 'jpeg':
        default:
          return pigeon.OutputFormat.jpeg;
      }
    }

    final api = pigeon.WatermarkApi();
    final req = pigeon.ComposeImageRequest(
      baseImage: inputImage,
      watermarkImage: watermarkImage,
      anchor: _anchorFromString(anchor),
      margin: margin,
      widthPercent: widthPercent,
      opacity: opacity,
      format: _formatFromString(format),
      quality: quality,
    );
    try {
      final res = await api.composeImage(req);
      return res.imageBytes;
    } on PlatformException catch (_) {
      // Fallback to legacy MethodChannel if Pigeon channel isn't set up.
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
}
