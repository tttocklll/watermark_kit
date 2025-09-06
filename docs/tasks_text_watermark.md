# Watermark Kit — Tasks: Text Watermark (Image)

Scope: Add native text watermark rendering for image composition on iOS. Keep existing image‑only API intact; add a parallel `composeText` path via Pigeon with MethodChannel fallback. No video in this phase.

## Plan
1) Pigeon schema
2) iOS implementation
3) Dart API + platform glue
4) Example app update
5) Tests & docs

## 1) Pigeon schema
- Edit `pigeons/messages.dart`:
  - Add `TextStyleDto`, `WmStyleDto`, `ComposeTextRequest` (see `docs/design_text_watermark_en.md`).
  - Add `composeText(ComposeTextRequest) : ComposeImageResult` to `WatermarkApi`.
- Regenerate:
  - `flutter pub get`
  - `dart run pigeon --input pigeons/messages.dart`
  - Verify updated files: `lib/gen/messages.g.dart`, `ios/Classes/Messages.g.swift`.

## 2) iOS implementation
- In `ios/Classes/WatermarkApiImpl.swift`:
  - Implement `composeText(request:completion:)`.
  - Convert DTOs → Swift types; map `Anchor`, `Unit`, `OutputFormat` as in image path.
  - Call a new helper on the plugin to render text → `CIImage`.
- In `ios/Classes/WatermarkKitPlugin.swift`:
  - Factor composition steps used by image path into a helper (e.g., `compose(base:overlay:anchor:margin:offset:units:opacity:format:quality:)`).
  - Add `renderTextCIImage(text: style: widthPercent: fontSizePt:) -> CIImage` using Core Text per design.
  - Keep existing `composeImage` unchanged.
- Optional MethodChannel fallback:
  - Add a new case `"composeText"` in `handle(_:)`, mirroring `composeImage` argument names, and reuse the same helpers.

## 3) Dart API + platform glue
- Update `lib/watermark_kit_platform_interface.dart`:
  - Add abstract `composeTextImage(...)` with parameters matching the design.
- Update `lib/watermark_kit_method_channel.dart`:
  - Build `pigeon.ComposeTextRequest` and call `WatermarkApi().composeText(...)`.
  - On `PlatformException`, fall back to `methodChannel.invokeMethod<Uint8List>('composeText', args)`.
- Update `lib/watermark_kit.dart`:
  - Public wrapper `composeTextImage(...)` forwarding to platform implementation.

## 4) Example app
- `example/lib/main.dart`:
  - Add a new section "Text Watermark" with a text field, font size slider (optional), stroke/shadow toggles.
  - Wire to `_watermarkKitPlugin.composeTextImage(...)`.
  - Keep current image‑watermark demo intact.

## 5) Tests & docs
- Golden tests (Dart):
  - Known base image; render text at each anchor; compare PNG bytes (allow small tolerance).
- iOS unit tests:
  - `renderTextCIImage` returns non‑empty image; alpha > 0 for glyph region; stroke/shadow toggles.
- Lints/format:
  - `dart format .` and `flutter analyze` pass.
- Docs:
  - README: usage snippet for `composeTextImage`.
  - Link to `docs/design_text_watermark_en.md` from README or `docs/main_spec.md` status note.

## Acceptance Checklist
- [ ] Pigeon codegen compiles; iOS/Dart agree on signatures.
- [ ] Compose text → bytes works on device and simulator (iOS 15+).
- [ ] Default sizing (`widthPercent=0.18`) and `fontSizePt` override both work.
- [ ] Anchor/margin/offset behave identical to image watermark path.
- [ ] Stroke/shadow/opacity behave as specified.
- [ ] Example app demonstrates end‑to‑end flow and saves output.
