## 2.2.0

Added
- **iOS & Android**: Animated GIF watermark support for video composition (per-frame overlay timing).
- Example app: added a bundled sample GIF for video watermark testing.

## 2.1.1

Fixed
- **iOS**: Resolved crash in `composeText` when converting colorArgb (0xFFFFFFFF) from Int64 to UInt32
  - Changed from unsafe `Int64 → Int32 → UInt32` conversion to idiomatic `UInt32(truncatingIfNeeded:)`
  - Fixes "Fatal error: Not enough bits to represent the passed value" crash
- **iOS**: Fixed text watermark clipping on right side
  - Improved canvas size calculation using `CTLineGetImageBounds` in addition to `CTLineGetTypographicBounds`
  - Ensures glyphs with italic, kerning, or ligatures are not clipped
  - Increased padding from 4.0 to 8.0 for safety margin

## 2.1.0

Improved
- **Android & iOS**: Significantly enhanced watermark quality for both images and videos
  - **Android**: High-quality filtering (FILTER_BITMAP_FLAG, DITHER_FLAG) with Matrix-based scaling for images; mipmaps + trilinear filtering (GL_LINEAR_MIPMAP_LINEAR) for video watermarks
  - **iOS**: CILanczosScaleTransform for superior quality scaling (replaces simple CGAffineTransform); highQualityDownsample option added to CIContext
  - Results in sharper, smoother watermarks with better detail preservation and anti-aliasing

Example
- Add save to gallery feature: users can now save watermarked images directly to their device photo library
  - Cross-platform implementation using `gal` package with proper permission handling
  - "Save to Gallery" button added to Result preview card

## 2.0.0

Added
- Android support for image, text, and video watermarking (API 24+).
  - Hardware Surface pipeline with automatic fallback to ByteBuffer YUV + GLES when needed.
  - Progress callbacks and cancellation, matching iOS.
  - Audio passthrough (best effort).

Fixed
- Android: prevent video tasks from hanging at 100% by properly propagating decoder EOS to the encoder.
- Android: corrected overlay vertical flip (image/text) so placement is upright while keeping coordinates unchanged.

Changed
- README updated for cross‑platform support; removed iOS‑only notes.
- Default logs reduced; added `WMLog` gate for verbose debugging on Android.

Notes
- Default codec is H.264; HEVC is used when supported. Some devices/emulators may not support HEVC/Dolby Vision.
- Minimum Android SDK is 24.

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
