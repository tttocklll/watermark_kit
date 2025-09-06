# Watermark Kit – 画像透かしタスク（iOS）

Scope: 画像入力と透かし画像の合成（iOS）。Core Image + Metal を使用し、PNG/JPEG を出力する。

1) Dart API（MethodChannel 経由。一部は後に Pigeon へ）
- `composeImage`（bytes→bytes）。
- Options: `anchor`, `margin`, `widthPercent`, `opacity`, `format`, `quality`, `offset{X,Y}`, `marginUnit`, `offsetUnit`。

2) iOS 実装（Swift）
- `CIImage` デコード、`widthPercent` に基づくスケール、`CISourceOverCompositing` で合成。
- `CIColorMatrix` でグローバル不透明度。
- PNG / JPEG エンコード、バイト列返却。

3) Example アプリ
- サンプル画像生成ボタン。
- `composeImage` 実行、temp に保存、画面表示。

4) ドキュメント
- `docs/main_spec.md` にデフォルト値とアンカー仕様の記載。

5) Pigeon への移行
- `pigeons/messages.dart` にスキーマを集約、`dart run pigeon` で生成。
- iOS: `WatermarkApi` 実装に接続。
- Dart: 生成クライアントへ置き換え、MethodChannel を整理。

6) 続きの改善
- ファイルパス入力、HEIF 出力、エラーマッピング整備、ゴールデン画像テスト。
