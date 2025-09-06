# Flutter Watermark Kit (iOS) — Detailed Design v1.0

Status: Draft
Date: 2025-09-06
Owner: watermark_kit

## 1. Overview

This document details the architecture and implementation plan for an iOS-only Flutter plugin that applies watermarks (text/bitmap/SVG) to images and videos using Core Image on a Metal-backed `CIContext`. It refines the high-level spec in `docs/main_spec.md` into concrete behaviors, data models, pipelines, defaults, and error handling suitable for an initial release with a clear upgrade path. While the implementation uses Metal for performance, the product name and API avoid emphasizing GPU.

Goals
- Fast, battery-efficient watermark composition using Core Image + Metal.
- No FFmpeg dependency. Lean binary size.
- Safe defaults; simple API for common cases; extensible for advanced needs.

Non-goals
- Android implementation.
- Animated or time-varying overlays.
- Advanced blend modes or shader authoring.
- Arbitrary SVG feature parity with desktop browsers.

## 2. Public API (Dart)

High-level Dart API mirrors `main_spec.md` with the following clarifications.

### 2.1 Types
- `HAlign { left, center, right }`
- `VAlign { top, center, bottom }`
- `Unit { px, percent }`

```dart
class WatermarkAnchor {
  final HAlign h;
  final VAlign v;
  final double margin;         // default 16
  final Unit unit;             // margin/offset units
  final Offset? offset;        // fine-tuning from anchor point
  const WatermarkAnchor({
    required this.h,
    required this.v,
    this.margin = 16,
    this.unit = Unit.px,
    this.offset,
  });
}

class WatermarkSize {
  const WatermarkSize.auto({
    this.fractionOfShortSide = 0.18, // default
    this.minPx = 64,
    this.maxPx = 512,
    this.preserveAspectRatio = true,
  });
  const WatermarkSize.fixedPx({
    required this.widthPx,
    this.preserveAspectRatio = true,
  });
  const WatermarkSize.percent({
    required this.widthPercent, // 0..1
    this.preserveAspectRatio = true,
  });
}

class WatermarkTextStyle {
  final String fontFamily; // e.g. ".SFUI" or registered custom font
  final double fontSize;   // points (pt)
  final FontWeight fontWeight;
  final Color color;
  const WatermarkTextStyle({
    this.fontFamily = ".SFUI",
    this.fontSize = 24,
    this.fontWeight = FontWeight.w600,
    this.color = const Color(0xFFFFFFFF),
  });
}

class WatermarkStyle {
  final double opacity;     // 0..1
  final bool stroke;        // enable outline
  final double strokeWidth; // px at output resolution
  final double shadowBlur;  // Gaussian blur radius
  // Potential minor version extensions:
  // final Color? strokeColor; final Color? shadowColor; final Offset? shadowOffset;
  const WatermarkStyle({
    this.opacity = 0.6,
    this.stroke = false,
    this.strokeWidth = 1.0,
    this.shadowBlur = 0.0,
  });
}

sealed class WatermarkSpec {
  const WatermarkSpec();
  factory WatermarkSpec.text(
    String text, {
    required WatermarkAnchor anchor,
    WatermarkTextStyle textStyle,
    WatermarkStyle style,
  }) = _TextSpec;
  factory WatermarkSpec.bitmap(
    ImageInput image, {
    required WatermarkAnchor anchor,
    WatermarkSize size,
    WatermarkStyle style,
  }) = _BitmapSpec;
  factory WatermarkSpec.svg(
    String svgDataOrPath, {
    required WatermarkAnchor anchor,
    WatermarkSize size,
    WatermarkStyle style,
  }) = _SvgSpec;
}
```

Overlay ordering: later entries in `overlays` are composited on top of earlier ones (source-over).

### 2.2 Image API
```dart
final wm = WatermarkKit.iOS();
final ImageResult result = await wm.processImage(
  input: ImageInput.file('/path/in.jpg'),
  overlays: [...],
  output: ImageOutput(format: ImageFormat.jpeg(quality: 0.9)),
  options: const ProcessOptions(),
);
// ImageResult: { String path, int width, int height, String format }
```

### 2.3 Video API
```dart
final controller = await wm.processVideo(
  input: VideoInput.file('/path/in.mp4'),
  overlays: [...],
  output: VideoOutput(codec: VideoCodec.hevc, fileType: FileType.mp4),
  options: const ProcessOptions(),
);
controller.progress.listen((p) => print('progress: $p')); // 0..1
// Optional: controller.cancel();
final VideoResult result = await controller.done; // { path, width, height, durationMs, codec }
```

### 2.4 Errors
```dart
sealed class WatermarkError implements Exception { const WatermarkError(); }
class UnsupportedFormatError extends WatermarkError {}
class CodecUnavailableError extends WatermarkError {} // e.g., HEVC not available
class OutOfMemoryError extends WatermarkError {}
class PermissionDeniedError extends WatermarkError {}
class InvalidArgumentError extends WatermarkError {}
class InternalNativeError extends WatermarkError { final String detail; InternalNativeError(this.detail); }
```

## 3. Platform Channels & DTOs

We will use Pigeon for type-safe bridges. Because sealed classes are not directly expressible, define DTOs with a discriminant:

```dart
enum OverlayType { text, bitmap, svg }
class OverlaySpecDto {
  final OverlayType type;
  final WatermarkAnchor anchor;
  final WatermarkStyle style;
  final WatermarkSize? size;      // for bitmap/svg
  final String? text;             // for text
  final WatermarkTextStyle? textStyle;
  final ImageInputDto? image;     // for bitmap
  final String? svgDataOrPath;    // for svg
}
```

Host API:
- `Future<ImageResultDto> processImage(ImageRequestDto req)`
- `Future<StartTokenDto> processVideoStart(VideoRequestDto req)` returning a token; progress and completion streamed via EventChannel. `cancel(token)` to abort.

## 4. Layout & Sizing Semantics

All positioning/sizing is evaluated against the pixel dimensions of the output image or the video’s clean aperture.

1) Compute target overlay width:
- `auto`: `widthPx = clamp(shortSide * fraction, minPx, maxPx)`.
- `fixedPx`: `widthPx` as-is.
- `percent`: `widthPx = imageWidth * widthPercent`.
Maintain aspect ratio if requested; otherwise, exact width is used and height follows intrinsic or SVG viewBox.

2) Compute anchor point:
- Horizontal: `left => x = margin`, `center => x = width/2`, `right => x = width - margin`.
- Vertical: `top => y = height - margin`, `center => y = height/2`, `bottom => y = margin`.
If `Unit.percent`, interpret `margin` and `offset` in [0..1] relative to image dimensions. Apply `offset` after anchor.

3) Place overlay rectangle with its reference corner at the anchor:
- For `(right,bottom)`, top-right corner aligns to anchor; adjust for overlay size accordingly. The same rule applies consistently across all anchor pairs.

4) Pixel snapping:
- Round final placement to integer pixels to avoid half-pixel blurring. Use Lanczos for downscale.

5) Z-order:
- `overlays[0]` composited first; the last entry is on top.

## 5. Text Rendering (iOS)

- Use `CoreText` with `NSAttributedString` to rasterize text onto an offscreen `CGBitmapContext` at 2x scale for crisp edges, then downsample to target width.
- Font lookup by PostScript or family name; fallback to `.SFUI` if not found.
- Stroke: if enabled, first draw stroke, then fill. Defaults use text color for fill and black (70% opacity) for stroke; a later version can expose `strokeColor`.
- Shadow: apply `NSShadow` on text draw or post-process with Core Image `CIGaussianBlur` using the alpha mask; V1.1 exposes `shadowColor` and `shadowOffset`.
- Multiline: current design targets single-line; a later version can add `maxWidthPx` and wrapping with `CTFramesetter`.
- Emoji and complex scripts rely on Core Text shaping; color emoji supported via Apple system fonts.

The rendered text image is converted to `CIImage` with premultiplied alpha and composited via `CISourceOverCompositing`.

## 6. Bitmap Overlay

- Inputs: PNG/JPEG/HEIF. Preserve alpha for PNG/HEIF.
- Load via `CIImage(contentsOf:)` or `CIImage(cgImage:)` ensuring a working color space (sRGB).
- Resize with `CILanczosScaleTransform` to target width.

## 7. SVG Overlay

- Rasterize SVG to `CGImage` at the required pixel size, convert to `CIImage` and composite.
- Library: prefer a lightweight, MIT-licensed library (e.g., SVGKit) vendored or added via SPM/CocoaPods. If dependency is not acceptable, implement a minimal subset parser for basic shapes/paths.
- Supported subset: paths, groups, fills (solid/linear gradient), strokes, viewBox, transforms. Exclude filters, external resources, and CSS.
- `svgDataOrPath`: if a path, load and parse; if inline XML, parse directly.

## 8. Image Pipeline

1) Decode input using `CGImageSource` to `CIImage`, honoring EXIF orientation by normalizing to .up at load time.
2) Configure `CIContext` with Metal (`CIContext(mtlDevice: ..., options: [ .workingColorSpace: sRGB ])`).
3) For each overlay: prepare `CIImage` (text/bitmap/svg), compute rect, composite with `CISourceOverCompositing`.
4) Export:
   - JPEG/PNG/HEIF via `CGImageDestination` with embedded sRGB ICC profile.
   - Quality settings (JPEG `quality`, PNG lossless, HEIF default quality 0.9). HEIF writes `.heic` by default.
5) Write atomically to destination; if `overwrite=false` and file exists, fail with `InvalidArgumentError`.

## 9. Video Pipeline

1) Reader: `AVAssetReader` + `AVAssetReaderTrackOutput`
   - Pixel format: BGRA (`kCVPixelFormatType_32BGRA`) for simplicity and Core Image compatibility.
   - Keep original frame rate and dimensions.

2) Writer: `AVAssetWriter` + `AVAssetWriterInput` (+ adaptor if needed)
   - Codec: requested (HEVC/H.264). If HEVC unavailable on device, throw `CodecUnavailableError` (or auto-fallback to H.264 if `options.allowFallback=true`).
   - Bitrate heuristic (default): min(sourceBitrate, recommended) where recommended ≈ 0.08 bpp × width × height × fps for H.264; use 0.06 bpp for HEVC. Keyframe interval: `2 × fps`.
   - Profile: H.264 High, Level auto; HEVC Main.

3) Audio: passthrough if container/codec compatible (MP4 + AAC). If incompatible, either transcode to AAC-LC @ 128–192 kbps (if `options.audioTranscodeIfNeeded=true`) or fail with `UnsupportedFormatError`.

4) Composition loop per sample buffer:
   - Create `CIImage` from `CVPixelBuffer`.
   - Composite overlays.
   - Render via `CIContext.render(_:to:bounds:colorSpace:)` into a `CVPixelBuffer` from the writer’s pool.
   - Append to writer with source time from the sample buffer.

5) Progress: based on processed video duration / total duration (simple and monotonic). Emit via `EventChannel`.

6) Cancellation: on `cancel()`, cancel reader and mark writer as failed, remove temp output, and complete `done` with an error.

7) Colors & HDR: normalize to 8-bit sRGB. Wide-gamut P3 and HDR10/HLG pass-through is out of scope for v1.0.

## 10. Defaults (Beginner-friendly)

- Anchor: bottom-right, `margin=16px`.
- Size: `auto(fractionOfShortSide=0.18, minPx=64, maxPx=512)`.
- Style: `opacity=0.6`, `stroke=false`.
- Video: keep source resolution/fps; codec `hevc` if available, else `h264` (if fallback enabled); bitrate heuristic as above.

## 11. Error Mapping

- Input file missing/unreadable → `InvalidArgumentError`.
- Unsupported format/container/codec → `UnsupportedFormatError`.
- HEVC not available → `CodecUnavailableError` (or fallback to H.264).
- No Photos permission (if used) → `PermissionDeniedError`.
- CI/Metal failures, writer failures → `InternalNativeError(detail)`.
- Memory pressure during render → `OutOfMemoryError`.

## 12. Performance & Memory

- Reuse `CIImage` and overlay rasters across frames (video) when overlays are static.
- Use Metal-backed `CIContext` singleton per processing session.
- Avoid unnecessary color space conversions; work in sRGB.
- Render video frames on a dedicated queue; keep latency low by honoring writer input’s `requestMediaDataWhenReady` callback.
- For 4K: ensure only one frame is in-flight when memory is tight; consider downscaling if requested in future versions.

## 13. Threading & Lifecycle

- Image: run on a background serial queue.
- Video: one reader queue, one writer queue, composition on a serial queue to maintain order.
- iOS backgrounding: for long exports (if initiated from an app), optionally use `beginBackgroundTask` to finish work when the app goes to background (not required if caller operates on files only).

## 14. File I/O

- Accept absolute or app-container-relative paths.
- Write to a temporary file first, then atomically move to destination.
- Option `overwrite: bool` (default false).

## 15. Testing Strategy

- Unit tests (Dart): anchor math, size computation, serialization to Pigeon DTOs.
- iOS unit tests: text raster correctness (glyph bounds), color/alpha preservation.
- Golden tests: image composition with small fixtures.
- Integration tests: short MP4 (720p) with overlays; verify duration, dimensions, and no frame drops.

## 16. Risks & Mitigations

- HEVC availability varies: implement fallback knob; document behavior.
- Audio passthrough incompatibility: detect and transcode or fail explicitly.
- SVG complexity: restrict to a safe subset; log unsupported features.
- Color management inconsistencies: normalize to sRGB; embed profile on image outputs.

## 17. Roadmap

- Android implementation with hardware acceleration (e.g., Vulkan/compute or GPU-backed filters).
- Advanced text: multiline, kerning, baseline shift, stroke/shadow color/offset API.
- Blend modes, rotation, tiling/repeat watermarks.
- Time-varying overlays for video (fade-in/out, keyframe API).
- HDR / P3 color support.
- Hardware capability probing API (query codecs, max throughput).
