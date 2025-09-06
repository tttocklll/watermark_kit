## 0.0.2

Added
- Text watermark support for images: new `WatermarkKit.composeTextImage(...)` API.
  - Placement options mirror `composeImage` (anchor, margin, offset, units).
  - Text style: `fontFamily`, `fontSizePt` (or `widthPercent` fit), `fontWeight`, `colorArgb`, `opacity`.
- Pigeon host method `WatermarkApi.composeText` and Dart client wiring (MethodChannel fallback retained).
- Example app: "Text Watermark" section and Compose Text action.

Changed/Chore
- README updated with text watermark usage and API reference.

## 0.0.1

Initial release.

Added
- iOS image watermarking plugin using Core Image (Metal-backed CIContext under the hood).
- Public API: `WatermarkKit.composeImage(...)` that composes a watermark image over a base image and returns encoded bytes.
  - Options: `anchor`, `margin` (with `marginUnit: 'px'|'percent'`), `widthPercent`, `opacity`, `offsetX/offsetY` (with `offsetUnit`), `format: 'png'|'jpeg'`, `quality` (JPEG).
  - Anchors: `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `center`.
- Pigeon-based typed bridge (Dart/Swift) for `composeImage`.
- Example app to pick base/watermark from gallery, tweak options, and preview the result.

Changed/Chore
- Simplified README to state iOS support without version numbers.
- Committed example iOS CocoaPods setup (Podfile/lock, xcconfig includes) for reproducible builds.
- Removed unused template tests and misc files; tightened .gitignore.
