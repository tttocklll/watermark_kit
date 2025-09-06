# watermark_kit

Image watermarking plugin for Flutter (iOS MVP). The MVP composes a watermark image over a base image and returns the encoded result. Video and text/SVG overlays are out of scope for the first milestone.

## API (MVP)

```
final wm = WatermarkKit();
final bytes = await wm.composeImage(
  inputImage: basePngBytes,
  watermarkImage: wmPngBytes,
  anchor: 'bottomRight',
  margin: 16,
  widthPercent: 0.18,
  opacity: 0.6,
  format: 'jpeg', // or 'png'
  quality: 0.9,
);
```

Anchors: `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `center`.

See `example/` for a runnable demo that generates images at runtime.
