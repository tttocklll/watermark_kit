## 1.0.0

Added
- iOS video watermarking with progress/cancel (Core Image + AVFoundation Reader/Writer)
  - Pigeon APIs: `composeVideo`, `cancel`, and `WatermarkCallbacks` (progress/completed/error)
  - Dart: `VideoTask` exposes `progress` Stream and `done` Future
  - Example: dedicated Video tab with text/image watermark selection and output preview player

Changed
- Package description updated to reflect image + video support
- iOS Podspec metadata (summary/homepage/author) updated; minimum iOS set to 15.0

Notes
- Default codec is H.264; `codec: 'hevc'` can be used where supported
- Audio is passed through on a best‑effort basis

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
