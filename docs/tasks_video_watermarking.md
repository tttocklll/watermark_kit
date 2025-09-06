# Watermark Kit – 動画ウォーターマーク実装タスク（iOS MVP）

対象: `docs/design/video_watermarking.md`（本仕様）/ `docs/main_spec.md` 準拠。まずは iOS 限定で動画に静的ウォーターマーク（画像/テキスト）を合成する。

---

## マイルストーン構成
- M0: スキーマ拡張＋コード生成（Pigeon）
- M1: iOS 合成パイプライン実装（Reader/Writer + CI）
- M2: Dart クライアント/API（進捗/キャンセル）＋ Example UI
- M3: テスト＆ドキュメント更新

---

## 作業ルール（ツール）
- コード検索・参照: serena MCP を使用（例: `serena__search_for_pattern`, `serena__find_symbol`, `serena__find_referencing_symbols`）。
- ライブラリ/API ドキュメント確認: Context7 を使用（`context7__resolve-library-id` → `context7__get-library-docs`）。該当ライブラリが未収載の場合は代替の一次情報に限定して参照。

---

## M0 スキーマ拡張（Pigeon）
- 追加ファイル/変更点
  - `pigeons/messages.dart`
    - enum: `VideoCodec { h264, hevc }`
    - class: `ComposeVideoRequest { inputVideoPath, outputVideoPath?, watermarkImage?, text?, anchor, margin, marginUnit, offsetX, offsetY, offsetUnit, widthPercent, opacity, codec, bitrateBps?, maxFps?, maxLongSide? }`
    - class: `ComposeVideoResult { taskId, outputVideoPath, width, height, durationMs, codec }`
    - `@FlutterApi` コールバック: `WatermarkCallbacks`
      - `onVideoProgress(String taskId, double progress, double etaSec)`
      - `onVideoCompleted(String taskId, ComposeVideoResult result)`
      - `onVideoError(String taskId, String code, String message)`
    - `@HostApi` 追加:
      - `@async ComposeVideoResult composeVideo(ComposeVideoRequest request)`
      - `void cancel(String taskId)`
- 受け入れ条件
  - `dart run pigeon --input pigeons/messages.dart` で `lib/gen/messages.g.dart` と `ios/Classes/Messages.g.swift` が生成される。
  - 既存 Image/Text API と互換（破壊的変更なし）。

---

## M1 iOS 実装（Reader/Writer + Core Image）
- 新規/更新ファイル
  - `ios/Classes/VideoWatermarkProcessor.swift`（新規）
    - `start(request: ComposeVideoRequest, callbacks: WatermarkCallbacks, taskId: String)`
    - `cancel(taskId: String)`
    - 構成:
      - 入力: `AVURLAsset`
      - デコード: `AVAssetReaderTrackOutput(kCVPixelFormatType_32BGRA)`
      - 合成: `CIContext`（Metal）+ `CISourceOverCompositing`、オーバーレイは事前スケール・位置確定
      - 出力: `AVAssetWriterInput`（H.264 既定 / HEVC オプション）+ `AVAssetWriterInputPixelBufferAdaptor`
      - 音声: `AVAssetReaderAudioMixOutput` → `AVAssetWriterInput` パススルー
      - 進捗: `sampleTime.seconds / duration.seconds` を `onVideoProgress` で Push
      - キャンセル: `cancel(taskId)` で Reader/Writer 停止＆一時出力削除
  - `ios/Classes/WatermarkApiImpl.swift`
    - `composeVideo` と `cancel` を追加し `VideoWatermarkProcessor` と `WatermarkCallbacks` を接続
  - `ios/Classes/WatermarkKitPlugin.swift`
    - 既存 `CIContext` をビデオ処理でも再利用（シングルトン）
- 受け入れ条件
  - 1080p/30fps/5s の入力で処理が成功し、出力 MP4 の再生が可能。
  - 進捗が 0→1.0 に単調増加し、完了時に `onVideoCompleted` が呼ばれる。
  - `cancel` 呼び出しで安全に停止し、中間ファイルが削除される。
  - 回転（`preferredTransform`）を尊重し、表示サイズ基準でアンカーが一致。

---

## M2 Dart クライアント/API + Example UI
- 新規/更新ファイル
  - `lib/watermark_kit_platform_interface.dart`
    - 動画 API を追加（インタフェース）:
      - `Future<VideoTask> composeVideo(ComposeVideoOptions ...)`
      - `Future<void> cancel(String taskId)`
  - `lib/watermark_kit_method_channel.dart`
    - Pigeon 経由で `composeVideo` を呼び出し、`WatermarkCallbacks` を `StreamController<double>` に橋渡し
    - Fallback: Pigeon 未初期化時は `PlatformException` を受け、未サポートエラーを投げる（動画は Pigeon 前提）
  - `lib/video_task.dart`（新規）
    - `class VideoTask { final String taskId; final Stream<double> progress; final Future<VideoResult> done; Future<void> cancel(); }`
    - `class VideoResult { final String path; final int width; final int height; final int durationMs; final String codec; }`
  - `lib/watermark_kit.dart`
    - Public API を追加（`composeVideo(...)` 戻り値は `VideoTask`）
  - `example/lib/main.dart`
    - 動画入力選択（ギャラリー/ファイルパス）と進捗バー、キャンセルボタン、完了後の再生/共有ボタンを追加
- 受け入れ条件
  - Example から動画を選択し、進捗が表示され、完了でファイルが作成される。
  - キャンセル操作で UI が停止し、ファイルが残らない。

---

## M3 テスト＆ドキュメント
- テスト
  - Dart: Pigeon 経路のシェイプ/イベントをモックで検証（`onVideoProgress` が 0→1.0 へ単調増加、`cancel` 呼び出しが iOS へ届く）
  - iOS: 2〜3 秒の 720p テスト動画で以下を XCTest:
    - 各アンカー配置のピクセル近傍が期待色
    - 進捗通知の単調性
    - キャンセル時の後片付け
- ドキュメント/メタ
  - `README.md` に動画対応の使い方/制約を追記
  - `CHANGELOG.md` にエントリ追加（iOS Video MVP）
  - `docs/main_spec.md` との整合コメント（現状アンカーは `topLeft/.../center` を継続。将来 `HAlign/VAlign` へ統合のメモ）
- 受け入れ条件
  - CI で Dart テストがグリーン
  - 手元検証で iOS 実機/シミュレータいずれかで Example 動作確認済み

---

## 実行コマンド例（開発メモ）
- コード生成（変更毎）
  - `dart run pigeon --input pigeons/messages.dart`
- Flutter Example 実行
  - `cd example && flutter run`

---

## 既知の注意点（実装時メモ）
- 既定コーデックは H.264（端末互換・再生互換が広い）。HEVC は明示オプション。
- `CIContext` は Metal バックエンドを 1 インスタンス再利用。
- 入力トラックの `preferredTransform` を `writerInput.transform` に適用し、表示座標系でアンカー計算。
- 色空間は sRGB 前提。厳密な色一致が必要なら将来 YUV パス対応を検討。

---

## 完了の定義（DoD）
- API/実装/Example/テスト/ドキュメントが本タスク内容で一貫し、`flutter test` が通る。
- 1080p/30fps/5s 入力でリアルタイムの 1.5〜3.0x 程度で完走（端末依存、目安）。
- クラッシュ/リソースリーク（ファイルハンドル/ピクセルバッファ等）が検査上見当たらない。
