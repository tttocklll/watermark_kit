import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gen/messages.g.dart' as pigeon;
import 'watermark_kit_platform_interface.dart';
import 'dart:typed_data';
import 'dart:async';
import 'video_task.dart';

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

    pigeon.MeasureUnit _unitFromString(String s) {
      switch (s) {
        case 'percent':
          return pigeon.MeasureUnit.percent;
        case 'px':
        default:
          return pigeon.MeasureUnit.px;
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
    // Primary path: Pigeon-generated API
    final api = pigeon.WatermarkApi();
    final req = pigeon.ComposeTextRequest(
      baseImage: inputImage,
      text: text,
      anchor: _anchorFromString(anchor),
      margin: margin,
      marginUnit: _unitFromString(marginUnit),
      offsetX: offsetX,
      offsetY: offsetY,
      offsetUnit: _unitFromString(offsetUnit),
      widthPercent: widthPercent,
      textStyle: pigeon.TextStyleDto(
        fontFamily: fontFamily,
        fontSizePt: fontSizePt,
        fontWeight: fontWeight,
        colorArgb: colorArgb,
      ),
      style: pigeon.WmStyleDto(
        opacity: opacity,
        stroke: false,
        strokeWidth: 1.0,
        shadowBlur: 0.0,
      ),
      format: _formatFromString(format),
      quality: quality,
    );
    try {
      final res = await api.composeText(req);
      return res.imageBytes;
    } on PlatformException catch (_) {
      // Fallback to legacy MethodChannel if Pigeon channel isn't set up.
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

  pigeon.MeasureUnit _unitFromString(String s) {
    switch (s) {
      case 'percent':
        return pigeon.MeasureUnit.percent;
      case 'px':
      default:
        return pigeon.MeasureUnit.px;
    }
  }
  // ---------------- Video API ----------------
  static final Map<String, _VideoTaskState> _tasks = {};
  static bool _callbacksInitialized = false;

  void _ensureCallbacksRegistered() {
    if (_callbacksInitialized) return;
    pigeon.WatermarkCallbacks.setUp(_CallbacksImpl());
    _callbacksInitialized = true;
  }

  String _genTaskId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = (now ^ 0x5f3759df).toUnsigned(32).toRadixString(16);
    return 'wm_${now}_${rand}';
  }

  @override
  Future<VideoTask> composeVideo({
    required String inputVideoPath,
    String? outputVideoPath,
    Uint8List? watermarkImage,
    String? text,
    String anchor = 'bottomRight',
    double margin = 16.0,
    String marginUnit = 'px',
    double offsetX = 0.0,
    double offsetY = 0.0,
    String offsetUnit = 'px',
    double widthPercent = 0.18,
    double opacity = 0.6,
    String codec = 'h264',
    int? bitrateBps,
    double? maxFps,
    int? maxLongSide,
  }) async {
    _ensureCallbacksRegistered();
    final taskId = _genTaskId();
    final ctrl = StreamController<double>.broadcast();
    final completer = Completer<VideoResult>();
    _tasks[taskId] = _VideoTaskState(ctrl, completer);

    pigeon.ComposeVideoRequest req = pigeon.ComposeVideoRequest(
      taskId: taskId,
      inputVideoPath: inputVideoPath,
      outputVideoPath: outputVideoPath,
      watermarkImage: watermarkImage,
      text: text,
      anchor: _anchorFromString(anchor),
      margin: margin,
      marginUnit: _unitFromString(marginUnit),
      offsetX: offsetX,
      offsetY: offsetY,
      offsetUnit: _unitFromString(offsetUnit),
      widthPercent: widthPercent,
      opacity: opacity,
      codec: (codec == 'hevc') ? pigeon.VideoCodec.hevc : pigeon.VideoCodec.h264,
      bitrateBps: bitrateBps,
      maxFps: maxFps,
      maxLongSide: maxLongSide,
    );

    // Fire-and-forget; completion will also complete the future
    unawaited(pigeon.WatermarkApi().composeVideo(req).then((res) {
      // Fallback completion in case onVideoCompleted wasn't received
      final st = _tasks[res.taskId];
      if (st != null && !st.completer.isCompleted) {
        st.ctrl.close();
        st.completer.complete(VideoResult(
          path: res.outputVideoPath,
          width: res.width,
          height: res.height,
          durationMs: res.durationMs,
          codec: res.codec == pigeon.VideoCodec.hevc ? 'hevc' : 'h264',
        ));
        _tasks.remove(res.taskId);
      }
    }).catchError((e, st) {
      // If error surfaces via returned Future
      final s = _tasks.remove(taskId);
      if (s != null && !s.completer.isCompleted) {
        s.ctrl.addError(e, st);
        s.ctrl.close();
        s.completer.completeError(e, st);
      }
    }));

    return VideoTask(
      taskId: taskId,
      progress: ctrl.stream,
      done: completer.future,
      cancel: () async {
        await pigeon.WatermarkApi().cancel(taskId);
      },
    );
  }

  @override
  Future<void> cancelVideo(String taskId) async {
    await pigeon.WatermarkApi().cancel(taskId);
  }
}

class _VideoTaskState {
  final StreamController<double> ctrl;
  final Completer<VideoResult> completer;
  _VideoTaskState(this.ctrl, this.completer);
}

class _CallbacksImpl extends pigeon.WatermarkCallbacks {
  @override
  void onVideoProgress(String taskId, double progress, double etaSec) {
    final st = MethodChannelWatermarkKit._tasks[taskId];
    st?.ctrl.add(progress);
  }

  @override
  void onVideoCompleted(pigeon.ComposeVideoResult result) {
    final st = MethodChannelWatermarkKit._tasks.remove(result.taskId);
    if (st != null && !st.completer.isCompleted) {
      st.ctrl.close();
      st.completer.complete(VideoResult(
        path: result.outputVideoPath,
        width: result.width,
        height: result.height,
        durationMs: result.durationMs,
        codec: result.codec == pigeon.VideoCodec.hevc ? 'hevc' : 'h264',
      ));
    }
  }

  @override
  void onVideoError(String taskId, String code, String message) {
    final st = MethodChannelWatermarkKit._tasks.remove(taskId);
    if (st != null && !st.completer.isCompleted) {
      final err = PlatformException(code: code, message: message);
      st.ctrl.addError(err);
      st.ctrl.close();
      st.completer.completeError(err);
    }
  }
}
