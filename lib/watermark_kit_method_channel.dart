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
    double offsetX = 0.0,
    double offsetY = 0.0,
    String marginUnit = 'px',
    String offsetUnit = 'px',
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

    pigeon.Unit _unitFromString(String s) {
      switch (s) {
        case 'percent':
          return pigeon.Unit.percent;
        case 'px':
        default:
          return pigeon.Unit.px;
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
      offsetX: offsetX,
      offsetY: offsetY,
      marginUnit: _unitFromString(marginUnit),
      offsetUnit: _unitFromString(offsetUnit),
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
        'offsetX': offsetX,
        'offsetY': offsetY,
        'marginUnit': marginUnit,
        'offsetUnit': offsetUnit,
      };
      final bytes = await methodChannel.invokeMethod<Uint8List>('composeImage', args);
      if (bytes == null) {
        throw PlatformException(code: 'compose_failed', message: 'No bytes returned');
      }
      return bytes;
    }
  }

  @override
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
  }) async {
    // Try Pigeon path if available (guarded to avoid hard dependency until codegen updated)
    try {
      // Dynamically check if composeText is wired by probing a dedicated BasicMessageChannel.
      // If not available, fall back to MethodChannel below.
      final basicChannel = const BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.watermark_kit.WatermarkApi.composeText',
        pigeon.WatermarkApi.pigeonChannelCodec,
      );
      final req = [
        inputImage,
        text,
        // Anchor (default bottomRight)
        pigeon.Anchor.values.indexOf(_anchorFromString(anchor)),
        margin,
        pigeon.Unit.values.indexOf(_unitFromString(marginUnit)),
        offsetX,
        offsetY,
        pigeon.Unit.values.indexOf(_unitFromString(offsetUnit)),
        widthPercent,
        // TextStyleDto
        [fontFamily, fontSizePt, fontWeight, colorArgb],
        // WmStyleDto (only opacity used in MVP path; others kept for forward compat)
        [opacity, false, 1.0, 0.0],
        pigeon.OutputFormat.values.indexOf(_formatFromString(format)),
        quality,
      ];
      final reply = await basicChannel.send(req) as List<Object?>?;
      if (reply != null && reply.isNotEmpty && reply[0] != null) {
        final res = reply[0] as List<Object?>;
        final bytes = res[0] as Uint8List;
        return bytes;
      }
      // else fall through to MethodChannel
    } catch (_) {
      // Ignore and use MethodChannel fallback
    }

    final args = <String, dynamic>{
      'inputImage': inputImage,
      'text': text,
      'anchor': anchor,
      'margin': margin,
      'marginUnit': marginUnit,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'offsetUnit': offsetUnit,
      'widthPercent': widthPercent,
      'opacity': opacity,
      'format': format,
      'quality': quality,
      'fontFamily': fontFamily,
      'fontSizePt': fontSizePt,
      'fontWeight': fontWeight,
      'colorArgb': colorArgb,
    };
    final bytes = await methodChannel.invokeMethod<Uint8List>('composeText', args);
    if (bytes == null) {
      throw PlatformException(code: 'compose_text_failed', message: 'No bytes returned');
    }
    return bytes;
  }

  // Helpers shared between methods
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

  pigeon.Unit _unitFromString(String s) {
    switch (s) {
      case 'percent':
        return pigeon.Unit.percent;
      case 'px':
      default:
        return pigeon.Unit.px;
    }
  }
}
