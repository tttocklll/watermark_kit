# watermark_kit

Lightweight image watermarking plugin for Flutter (iOS only). Composes an image or text watermark over a base image entirely in memory and returns encoded bytes. Built on Core Image with a Metal-backed context under the hood; no FFmpeg dependency.

## Platform Support

- iOS (Swift)
- Android: not implemented (invoking the API on Android will throw `MissingPluginException`).

## Install

In your app's `pubspec.yaml`:

```
dependencies:
  watermark_kit: ^1.0.0
```

Import and create the API:

```
import 'package:watermark_kit/watermark_kit.dart';

final wm = WatermarkKit();
```

## Quick Start

Image watermark (PNG/JPEG bytes → bytes):

```dart
final bytes = await wm.composeImage(
  inputImage: baseBytes,        // Uint8List (PNG/JPEG/HEIF usually supported by iOS)
  watermarkImage: wmBytes,      // Uint8List with alpha support (e.g., PNG)
  anchor: 'bottomRight',        // 'topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight' | 'center'
  margin: 0.05,                 // 5% margin when marginUnit == 'percent'
  marginUnit: 'percent',        // 'px' | 'percent' (default: 'px')
  widthPercent: 0.18,           // watermark width = 18% of base width
  opacity: 0.6,                 // 0..1 applied to watermark alpha
  offsetX: 0.0,                 // additional shift from anchor (see offsetUnit)
  offsetY: 0.0,
  offsetUnit: 'px',             // 'px' | 'percent' (default: 'px')
  format: 'png',                // 'png' | 'jpeg'
  quality: 0.9,                 // JPEG only
);
```

Write to a file if you want:

```dart
final file = File('/tmp/composed.png');
await file.writeAsBytes(bytes);
```

See the runnable `example/` app for a simple UI and usage.

Text watermark (text → bytes):

```dart
final textBytes = await wm.composeTextImage(
  inputImage: baseBytes,
  text: '© watermark kit',
  anchor: 'bottomRight',
  margin: 16.0,
  widthPercent: 0.18,        // target text width = 18% of base width
  opacity: 0.6,              // global alpha after raster
  format: 'jpeg',            // or 'png'
  fontFamily: '.SFUI',       // optional
  fontSizePt: 24.0,          // used if widthPercent is not provided
  fontWeight: 600,           // 100..900
  colorArgb: 0xFFFFFFFF,     // ARGB32
);
```

### Video

Add a text or image watermark to every frame of a video and export an MP4 file. The call returns a `VideoTask` with a `progress` stream and a `done` future.

Text watermark example:
```dart
final task = await wm.composeVideo(
  inputVideoPath: '/path/in.mp4',
  text: '© watermark_kit',        // use `text` OR `watermarkImage`
  anchor: 'bottomRight',           // 'topLeft'|'topRight'|'bottomLeft'|'bottomRight'|'center'
  margin: 16.0,                    // px (use 'percent' in marginUnit for relative)
  marginUnit: 'px',                // 'px' | 'percent'
  widthPercent: 0.18,              // watermark width = 18% of video display width
  opacity: 0.6,                    // 0..1
  codec: 'h264',                   // or 'hevc' when supported
);
task.progress.listen((p) => print('progress: ${(p * 100).toStringAsFixed(0)}%'));
final res = await task.done;
print('Output: ${res.path} (${res.width}x${res.height})');
```

Image watermark example:
```dart
final wmBytes = await File('/path/wm.png').readAsBytes();
final task = await wm.composeVideo(
  inputVideoPath: '/path/in.mp4',
  watermarkImage: wmBytes,         // PNG with alpha recommended
  anchor: 'topLeft',
  margin: 24.0,
  widthPercent: 0.15,
  opacity: 0.8,
);
final res = await task.done;
```

Cancelling:
```dart
final task = await wm.composeVideo(inputVideoPath: '/path/in.mp4', text: '© …');
final sub = task.progress.listen((p) { /* update UI */ });
// ... some condition
await task.cancel();
await sub.cancel();
```

Options (quick reference):
- `inputVideoPath` (String, required): input MP4 path (H.264/HEVC).
- `watermarkImage` (Uint8List?) or `text` (String?): choose either image or text.
- `anchor` (String): 'topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight' | 'center'. Default 'bottomRight'.
- `margin` (double) + `marginUnit` ('px'|'percent'): distance from edges at the anchor. Default 16.0 px.
- `offsetX` / `offsetY` (double) + `offsetUnit` ('px'|'percent'): fine adjustments. Default 0.
- `widthPercent` (double): watermark width relative to video display width. Default 0.18.
- `opacity` (double): 0..1, multiplies watermark alpha. Default 0.6.
- `codec` ('h264'|'hevc'): default 'h264'.

Notes:
- Set `codec: 'hevc'` for HEVC when supported; default is H.264.
- Audio is passed through on a best‑effort basis.
- Rotation is respected via the track `preferredTransform` (anchors apply to the displayed orientation).
- See the example app’s “Video” tab for a complete, working UI.

## API Reference
Method: `Future<Uint8List> composeImage({...})`

Parameters:
- `inputImage` (Uint8List, required): Base image bytes. PNG/JPEG recommended (HEIF may work depending on iOS codecs).
- `watermarkImage` (Uint8List, required): Watermark image bytes. PNG with transparency recommended.
- `anchor` (String): One of `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `center`. Default: `bottomRight`.
- `margin` (double): Margin from the edges around the anchor. Default: `16.0`.
- `marginUnit` (String): `'px'` or `'percent'`. Default: `'px'`.
  - If `'percent'`: horizontal margin = `margin * baseWidth`, vertical margin = `margin * baseHeight`.
- `widthPercent` (double): Target watermark width as a fraction of the base width (0..1). Default: `0.18`.
- `opacity` (double): 0..1, multiplies watermark alpha. Default: `0.6`.
- `offsetX`, `offsetY` (double): Additional X/Y offset from the anchored position. Default: `0.0`.
- `offsetUnit` (String): `'px'` or `'percent'` (applies to both X and Y). Default: `'px'`.
- `format` (String): `'png'` or `'jpeg'`. Default: `'jpeg'`.
- `quality` (double): JPEG quality (0..1). Default: `0.9`.

Returns:
- `Uint8List` — encoded output image.

Errors:
- Throws `PlatformException` with codes like `decode_failed`, `invalid_image`, `encode_failed`, `compose_failed` on native failures.

Method: `Future<Uint8List> composeTextImage({...})`

Parameters (in addition to placement/format options shared with `composeImage`):
- `text` (String, required): Watermark text (single line in MVP).
- `widthPercent` (double): Fit rendered text width to a fraction of base width (0..1). Default `0.18`.
- `fontFamily` (String): System or custom registered font name. Default `.SFUI`.
- `fontSizePt` (double): Point size if you prefer absolute sizing; ignored when `widthPercent` is provided.
- `fontWeight` (int): 100..900; mapped to iOS font weights. Default 600 (semibold).
- `colorArgb` (int): ARGB32 color; default white.
- `opacity` (double): 0..1 applied to the rendered text alpha.

Returns: `Uint8List` — encoded output image.

## Notes & Tips

- Watermark scaling is based on the base image width: `outputWatermarkWidth = widthPercent * baseWidth`.
- Alpha is preserved for PNG watermark images.
- The plugin works fully in memory and does not require Photos permissions. Any permissions you see in `example/` are only for picking/saving images.
 

## Limitations

- iOS only in this version; Android is not implemented.
- SVG overlays are not implemented yet.
- Text is single-line in the current MVP (no wrapping).

## Example App

`example/` includes a minimal UI that lets you pick a base image and a watermark image, tweak options, and preview the result. It is intended for manual testing and does not represent best-practice UI.

## Development

This plugin uses Pigeon for a type-safe platform bridge. Generated files live under `lib/gen/` (Dart) and `ios/Classes/` (Swift). When changing the schema in `pigeons/messages.dart`, re-generate via:

```
dart run pigeon --input pigeons/messages.dart
```

## License

See LICENSE.
