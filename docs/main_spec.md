# Flutter Watermark Kit (iOS版) – 仕様書（v1.0）

## 目的

* Flutter から **画像・動画**に高速に透かし（テキスト / 画像 / SVG）を合成できるプラグイン。
* iOS ネイティブでは **Core Image + Metal** を使い、**FFmpeg依存なし**、配布サイズを軽く、省電力かつ高速に動作させる。

---

## サポート範囲

* プラットフォーム: iOS 15.0+
* メディア入力: JPEG / PNG / HEIF（画像）、H.264 / HEVC MP4（動画）
* 出力: JPEG / PNG / HEIF（画像）、H.264 / HEVC MP4（動画）
* 音声はコピー（非変換）

---

## Flutter API デザイン

### 1. アンカー (配置)

```dart
enum HAlign { left, center, right }
enum VAlign { top, center, bottom }
enum Unit { px, percent }

class WatermarkAnchor {
  final HAlign h;      // 横軸: left/center/right
  final VAlign v;      // 縦軸: top/center/bottom
  final double margin; // 端からの距離 (既定: 16)
  final Unit unit;     // margin/offset の単位
  final Offset? offset; // 基準点からの微調整 (任意)

  const WatermarkAnchor({
    required this.h,
    required this.v,
    this.margin = 16,
    this.unit = Unit.px,
    this.offset,
  });
}
```

* **margin** … アンカー点を外枠から内側へ寄せる距離
* **offset** … さらに自由に微調整（上下左右）
* **unit** … `px` = 解像度依存, `percent` = 元画像サイズに比例

---

### 2. サイズ (透かし入力)

```dart
class WatermarkSize {
  const WatermarkSize.auto({
    this.fractionOfShortSide = 0.18, // 短辺の割合 (既定)
    this.minPx = 64,                 // 最小保証
    this.maxPx = 512,                // 最大制限
    this.preserveAspectRatio = true,
  });

  const WatermarkSize.fixedPx({
    required this.widthPx,
    this.preserveAspectRatio = true,
  });

  const WatermarkSize.percent({
    required this.widthPercent,       // 0..1
    this.preserveAspectRatio = true,
  });
}
```

* デフォルトは **短辺の18% 幅**で縮小、最小64px / 最大512px にクランプ。
* アスペクト比は常に維持。

---

### 3. 透かしの種類

```dart
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

#### Text Style

```dart
class WatermarkTextStyle {
  final String fontFamily;
  final double fontSize;    // pt単位 or 短辺比率を選べる (オプション)
  final FontWeight fontWeight;
  final Color color;
  const WatermarkTextStyle({
    this.fontFamily = ".SFUI",
    this.fontSize = 24,
    this.fontWeight = FontWeight.w600,
    this.color = const Color(0xFFFFFFFF),
  });
}
```

#### Style 共通

```dart
class WatermarkStyle {
  final double opacity;      // 透過度 (0..1)
  final bool stroke;         // 縁取り
  final double strokeWidth;
  final double shadowBlur;
  const WatermarkStyle({
    this.opacity = 0.6,
    this.stroke = false,
    this.strokeWidth = 1.0,
    this.shadowBlur = 0.0,
  });
}
```

---

### 4. 画像API

```dart
final wm = WatermarkKit.iOS();

final ImageResult result = await wm.processImage(
  input: ImageInput.file('/path/in.jpg'),
  overlays: [
    WatermarkSpec.text(
      '© picon inc.',
      anchor: WatermarkAnchor(h: HAlign.right, v: VAlign.bottom),
    ),
    WatermarkSpec.bitmap(
      ImageInput.asset('assets/logo.png'),
      anchor: WatermarkAnchor(h: HAlign.left, v: VAlign.top),
    ),
  ],
  output: ImageOutput(format: ImageFormat.jpeg(quality: 0.9)),
);
print(result.path); // 出力ファイルパス
```

---

### 5. 動画API（進捗つき）

```dart
final controller = await wm.processVideo(
  input: VideoInput.file('/path/in.mp4'),
  overlays: [
    WatermarkSpec.svg('<svg>...</svg>',
      anchor: WatermarkAnchor(h: HAlign.center, v: VAlign.center),
    ),
  ],
  output: VideoOutput(codec: VideoCodec.hevc, fileType: FileType.mp4),
);

controller.progress.listen((p) => print('progress: $p')); // 0.0-1.0
final VideoResult result = await controller.done;
print(result.path);
```

---

### 6. エラー

```dart
sealed class WatermarkError implements Exception {
  const WatermarkError();
}
class UnsupportedFormatError extends WatermarkError {}
class OutOfMemoryError extends WatermarkError {}
class PermissionDeniedError extends WatermarkError {}
class InternalNativeError extends WatermarkError {
  final String detail;
  InternalNativeError(this.detail);
}
```

---

## ネイティブ実装概要（iOS）

* 画像: `CIImage` + `CIFilter` で合成 → `CIContext` 経由で出力。
* 動画: `AVAssetReader` → `CIContext` 合成 → `AVAssetWriter`。
* 音声: コピー (パススルー)。
* CIContext は Metal バックエンドを使用。
* サイズ計算: `WatermarkSize.auto` → 短辺基準でクランプ。

---

## デフォルト値（初心者向けに安全）

* Anchor: bottomRight, margin=16px
* サイズ: `auto(fractionOfShortSide=0.18, minPx=64, maxPx=512)`
* Style: opacity=0.6, stroke=false

---

✅ この仕様で、ユーザーは「アンカー＋margin＋offset」＋「Autoサイズ」だけでシンプルに使える。
特殊な用途だけ `fixedPx` や `%` を選べばいいので、学習コストも低い。
