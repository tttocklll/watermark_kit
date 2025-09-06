# Text Watermark — Design (iOS)

Status: Proposed
Date: 2025-09-06
Owner: watermark_kit
Scope: Add native text watermark support for image composition on iOS (no video in this phase). Aligns with `docs/main_spec.md` and fits current image-only code.

## 1. Goals & Non‑Goals
- Goals
  - Render a single text overlay on an input image using Core Text on iOS, then composite via Core Image (Metal‑backed `CIContext`).
  - Keep API surface small and consistent with existing `composeImage` parameters (anchor, margin, offsets, opacity, format).
  - Reasonable defaults; crisp text (2x offscreen raster + downsample) and simple outline/shadow effects.
- Non‑Goals (this phase)
  - Multiple overlays / arrays and z‑ordering.
  - Video processing.
  - Multiline text/layout, wrap, max width, advanced typography controls.
  - Custom stroke/shadow colors (will use sensible defaults).

## 2. Public API (Dart)
Add a new method to `WatermarkKit`:

```dart
Future<Uint8List> composeTextImage({
  required Uint8List inputImage,
  required String text,
  // Placement
  String anchor = 'bottomRight',      // topLeft/topRight/bottomLeft/bottomRight/center
  double margin = 16.0,               // px or percent
  String marginUnit = 'px',           // 'px' | 'percent'
  double offsetX = 0.0,
  double offsetY = 0.0,
  String offsetUnit = 'px',           // 'px' | 'percent'
  // Sizing: either widthPercent or fontSizePt (if both set, widthPercent wins)
  double? widthPercent,               // 0..1 (default: 0.18)
  double? fontSizePt,                 // points; if null, derived from widthPercent
  // Text style
  String fontFamily = '.SFUI',
  int fontWeight = 600,               // 100..900 (maps to CTFont weight)
  int colorArgb = 0xFFFFFFFF,         // ARGB32
  // Effect/style
  double opacity = 0.6,               // 0..1 (applied post‑raster to alpha)
  bool stroke = false,
  double strokeWidth = 1.0,           // px (render scale aware)
  double shadowBlur = 0.0,            // px Gaussian blur on alpha
  // Output
  String format = 'jpeg',             // 'jpeg' | 'png'
  double quality = 0.9,               // JPEG only
});
```

Notes
- Default sizing uses `widthPercent = 0.18` if neither widthPercent nor fontSizePt provided.
- `fontWeight` maps to iOS weights; invalid values clamp to 400..700 range.
- `colorArgb` uses sRGB.

## 3. Platform Channels (Pigeon)
Extend `pigeons/messages.dart` with a new request/response and host API method (leaving existing image‑only API intact):

```dart
enum Anchor { topLeft, topRight, bottomLeft, bottomRight, center }
enum OutputFormat { jpeg, png }
enum Unit { px, percent }

class TextStyleDto {
  String fontFamily;
  double fontSizePt;   // if 0, ignored
  int fontWeight;      // 100..900
  int colorArgb;       // ARGB32
}

class WmStyleDto {
  double opacity;      // 0..1
  bool stroke;
  double strokeWidth;  // px
  double shadowBlur;   // px
}

class ComposeTextRequest {
  Uint8List baseImage;
  String text;
  Anchor anchor;
  double margin;
  Unit marginUnit;
  double offsetX;
  double offsetY;
  Unit offsetUnit;
  double widthPercent; // if 0, use textStyle.fontSizePt
  TextStyleDto textStyle;
  WmStyleDto style;
  OutputFormat format;
  double quality;
}

@HostApi()
abstract class WatermarkApi {
  @async
  ComposeImageResult composeImage(ComposeImageRequest request);

  @async
  ComposeImageResult composeText(ComposeTextRequest request);
}
```

Behavior
- If `widthPercent > 0`, size the rendered text to `baseWidth * widthPercent`; otherwise rasterize at `textStyle.fontSizePt`.
- Return the same `ComposeImageResult` payload (bytes, width, height) as image path.

Fallback
- Keep a legacy `MethodChannel('watermark_kit')` method name `composeText` with the same field names for environments where Pigeon wiring is not present.

## 4. iOS Rendering & Composition

Text Rasterization
- Build `NSAttributedString` from `text`, with `CTFont` created from `fontFamily` (fall back to `.SFUI`) and weight derived from `fontWeight`.
- Measure single‑line bounds via `CTLineCreateWithAttributedString` and `CTLineGetGlyphBounds`/`CTLineGetTypographicBounds`.
- Offscreen bitmap context at 2× scale in sRGB; transparent background, premultiplied alpha.
- Effects
  - Stroke: first stroke then fill. Default stroke color = black at 70% opacity; fill color = `colorArgb`.
  - Shadow: if `shadowBlur > 0`, blur the alpha mask via `CIGaussianBlur` after render and composite blurred alpha behind the text; default shadow color = black at 50%.

Sizing
- Width‑based: render at a comfortable base size (e.g., 64 pt), measure, compute `scale = targetWidth / renderedWidth`, and downsample with `CILanczosScaleTransform`.
- Font‑size‑based: render at `fontSizePt` directly (still at 2× for sharpness).

Composition
- Convert raster to `CIImage` with premultiplied alpha.
- Apply global `opacity` via `CIColorMatrix` to alpha.
- Compute placement rect from `anchor`, `margin`/`offset` with Unit conversion (same as image watermark), snap to integer pixels, and composite using `CISourceOverCompositing`.
- Export via `CGImageDestination` with embedded sRGB profile.

## 5. Defaults & Limitations
- Defaults
  - `anchor=bottomRight`, `margin=16px`, `widthPercent=0.18` (when `fontSizePt` not provided), `opacity=0.6`, `stroke=false`, `format=jpeg`, `quality=0.9`.
- Limitations (Phase 1)
  - Single‑line only; no wrapping/clipping.
  - Effects use fixed colors (stroke/shadow). V1.1 can expose colors and offsets.
  - No kerning/letterSpacing/baseline APIs (system defaults apply).

## 6. Error Handling
- Decode failures → `compose_failed` (Pigeon: `PigeonError` with code `compose_failed`).
- Empty text or invisible (zero width) → `invalid_arguments`.
- Font resolution failure → fall back to `.SFUI` without error; if no font at all, `compose_failed`.
- Rendering/compositing failures → `render_failed` or `filter_error` as appropriate.

## 7. Testing Strategy
- Golden images: simple phrases at known anchors; compare against baseline PNGs (tolerant threshold for raster diffs).
- Bounds/anchor math unit tests on Dart for placement equivalence with image watermark path.
- iOS unit test: verify glyph rendering doesn’t produce empty alpha; sample stroke/shadow toggles.

## 8. Migration Path (Later)
- Phase 2: generalize to multiple overlays using a discriminated DTO (`OverlaySpecDto { type: text|bitmap|svg, ... }`) and arrays. Reuse the same text and style DTOs. Keep `composeTextImage` as convenience wrapper.

---
This design deliberately mirrors existing image‑only semantics to keep the first increment small while laying a DTO/API foundation we can extend to overlay arrays and video.
