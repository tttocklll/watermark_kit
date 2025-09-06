# watermark_kit

Lightweight image watermarking plugin for Flutter (iOS only). Composes a watermark image over a base image entirely in memory and returns encoded bytes. Built on Core Image with a Metal-backed context under the hood; no FFmpeg dependency.

## Platform Support

- iOS (Swift)
- Android: not implemented (invoking the API on Android will throw `MissingPluginException`).

## Install

In your app's `pubspec.yaml`:

```
dependencies:
  watermark_kit: ^0.0.x
```

Import and create the API:

```
import 'package:watermark_kit/watermark_kit.dart';

final wm = WatermarkKit();
```

## Quick Start

Compose two in-memory images and get the result as bytes:

```
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

```
final file = File('/tmp/composed.png');
await file.writeAsBytes(bytes);
```

See the runnable `example/` app for a simple UI and usage.

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

## Notes & Tips

- Watermark scaling is based on the base image width: `outputWatermarkWidth = widthPercent * baseWidth`.
- Alpha is preserved for PNG watermark images.
- The plugin works fully in memory and does not require Photos permissions. Any permissions you see in `example/` are only for picking/saving images.
 

## Limitations

- iOS only in this version; Android is not implemented.
- Image → Image composition only (no video, no text/SVG overlays yet).
- Output formats: PNG or JPEG.

## Example App

`example/` includes a minimal UI that lets you pick a base image and a watermark image, tweak options, and preview the result. It is intended for manual testing and does not represent best-practice UI.

## Development

This plugin uses Pigeon for a type-safe platform bridge. Generated files live under `lib/gen/` (Dart) and `ios/Classes/` (Swift). When changing the schema in `pigeons/messages.dart`, re-generate via:

```
dart run pigeon --input pigeons/messages.dart
```

## License

See LICENSE.
