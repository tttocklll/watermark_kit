# watermark_kit: 動画ウォーターマーク設計 (iOS)

本ドキュメントは、現在の画像ウォーターマーク機能（iOS / Core Image / Pigeon ブリッジ）を踏まえ、動画に対しても同等の配置・スケーリング・不透明度制御を行う機能を追加する設計案です。最初の範囲は iOS のみ（Android は非対象）とし、Flutter 側 API は将来のマルチプラットフォーム化を見据え Pigeon で型安全に定義します。

現状の「仕様（main_spec）」として本リポジトリに明示ファイルは見当たらなかったため、以下を準拠元とします。
- Pigeon スキーマ: `pigeons/messages.dart`
- iOS 実装: `ios/Classes/WatermarkKitPlugin.swift`, `ios/Classes/WatermarkApiImpl.swift`
- Dart クライアント: `lib/*.dart`
- README の API/制約

## 目標 (Goals)
- 入力動画の全フレームに静的なウォーターマーク（画像/テキスト）を重ね、H.264/HEVC で再エンコードした動画をファイルとして出力する。
- 画像と同一の配置パラメータ（`anchor`/`margin`/`marginUnit`/`widthPercent`/`opacity`/`offset{X,Y}`/`offsetUnit`）を保つ。
- できるだけ高速（Metal バックエンドの CIContext 再利用、1 パス処理、ピクセルバッファプール再利用）。
- UI スレッドをブロックせず、進捗通知とキャンセルに対応する。

## 非目標 (Non‑Goals)
- 動的ウォーターマーク（時間変化・動き・アニメーション）。
- 可変テキスト（時刻挿入等）/複数レイヤー/ブレンドモード拡張。
- 音声編集（基本はパススルー）。
- DRM/暗号化、字幕焼き込み、透かし除去耐性の保証。

## 全体アーキテクチャ

iOS 側は AVFoundation の AssetReader/Writer を用いた 1 パス合成パイプラインを採用します。Core Image を Metal デバイスで動作させ、`CISourceOverCompositing` でオーバーレイ合成します。

1. 入力: `AVURLAsset`（`inputVideoPath`）
2. デコード: `AVAssetReaderTrackOutput`（`kCVPixelFormatType_32BGRA`）
3. オーバーレイ準備:
   - 画像透かし: 入力 PNG から `CIImage` を生成
   - テキスト透かし: 既存の `renderTextCGImage(...)` で PNG を生成 → `CIImage` 化
   - 動画の「表示サイズ」（トラックの `preferredTransform` を考慮した横幅）に対して `widthPercent` で一度だけスケール計算。配置も一度だけ幾何を確定。
4. 各フレーム処理:
   - `CVPixelBuffer` → `CIImage`
   - 事前計算済みのオーバーレイに平行移動を適用
   - `CISourceOverCompositing`
   - `CIContext.render` で `CVPixelBuffer`（プール再利用）へ描画
5. エンコード: `AVAssetWriterInput`（H.264 既定。HEVC はオプション）＋ `AVAssetWriterInputPixelBufferAdaptor`
6. 音声: `AVAssetReaderAudioMixOutput` → `AVAssetWriterInput` でパススルー
7. 進捗: 読み出した `CMSampleBuffer` のプレゼンテーション時刻 / 総尺で 0..1 を算出し Flutter へ通知
8. 完了: 出力 `outputVideoPath` を返す

### 代替案の検討
- `AVAssetExportSession + AVVideoComposition`：コード量は減るが、CIContext の再利用・フレーム制御・進捗/キャンセルの扱いで制約が増える。採用案は Reader/Writer。

## スレッド/非ブロッキング設計
- iOS: 専用 `DispatchQueue(label: "wm.video", qos: .userInitiated)` 上で処理。コールバックは Main キューへ返却。
- 長時間タスクのため、ハンドル（`taskId: String`）で識別し、キャンセル可能にする（`taskMap[taskId]` に状態保持）。
- 進捗は Pigeon の `@FlutterApi` で Push（`onVideoProgress(taskId, progress, etaSec)`）。

## API 仕様（Dart / Pigeon）

Pigeon 拡張（新規）:
```dart
enum VideoCodec { h264, hevc }

class ComposeVideoRequest {
  ComposeVideoRequest({
    required this.inputVideoPath,
    String? outputVideoPath, // null なら一時ディレクトリに生成
    required this.watermarkImage, // or null when text case
    String? text,
    Anchor anchor = Anchor.bottomRight,
    double margin = 16.0,
    Unit marginUnit = Unit.px,
    double offsetX = 0.0,
    double offsetY = 0.0,
    Unit offsetUnit = Unit.px,
    double widthPercent = 0.18,
    double opacity = 0.6,
    VideoCodec codec = VideoCodec.h264,
    int? bitrateBps,
    double? maxFps,
    int? maxLongSide, // リサイズ上限（例: 1920）
  });
  String inputVideoPath;
  String? outputVideoPath;
  Uint8List? watermarkImage;
  String? text;
  Anchor anchor;
  double margin;
  Unit marginUnit;
  double offsetX;
  double offsetY;
  Unit offsetUnit;
  double widthPercent;
  double opacity;
  VideoCodec codec;
  int? bitrateBps;
  double? maxFps;
  int? maxLongSide;
}

class ComposeVideoResult {
  ComposeVideoResult({
    required this.taskId,
    required this.outputVideoPath,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.codec,
  });
  String taskId;
  String outputVideoPath;
  int width;
  int height;
  int durationMs;
  VideoCodec codec;
}

@HostApi()
abstract class WatermarkApi {
  @async ComposeImageResult composeImage(ComposeImageRequest request);
  @async ComposeImageResult composeText(ComposeTextRequest request);
  @async ComposeVideoResult composeVideo(ComposeVideoRequest request);
  @async void cancel(String taskId);
}

@FlutterApi()
abstract class WatermarkCallbacks {
  void onVideoProgress(String taskId, double progress, double etaSec);
  void onVideoCompleted(String taskId);
  void onVideoError(String taskId, String code, String message);
}
```

Dart クライアント（新規/拡張）:
- `Future<ComposeVideoHandle> composeVideo({...})`
  - 引数は `ComposeVideoRequest` に準拠
  - 返り値 `ComposeVideoHandle { String taskId; Stream<double> progress; Future<String> done; void cancel(); }`
- 進捗は `WatermarkCallbacks` を `StreamController` に橋渡し

例:
```dart
final handle = await wm.composeVideo(
  inputVideoPath: input,
  watermarkImage: overlayPng,
  // or text: '© example'
  anchor: 'bottomRight',
  marginUnit: 'percent',
  margin: 0.04,
  widthPercent: 0.18,
  codec: 'h264',
);
handle.progress.listen((p) { /* update UI */ });
final outPath = await handle.done; // 完了待ち
```

## iOS 実装詳細

クラス構成（新規）:
- `VideoWatermarkProcessor.swift`
  - `start(request: ComposeVideoRequest, callbacks: WatermarkCallbacks, taskId: String)`
  - `cancel(taskId: String)`
  - 内部で Reader/Writer/Adaptor/CIContext をセットアップ

主要ポイント:
- `CIContext` は既存 `WatermarkKitPlugin` と同様に Metal デバイスで 1 インスタンス再利用。
- 入力 `AVAssetTrack` の `preferredTransform` を尊重。`writerInput.transform = videoTrack.preferredTransform` を設定し、座標系は「表示後の幅/高さ」を基準としてアンカー計算。
- オーバーレイ `CIImage` は一度だけ `widthPercent` でスケールし、不透明度は `CIColorMatrix` の A ベクトルで適用。
- ピクセルフォーマット: `kCVPixelFormatType_32BGRA` を採用（CI との相性良好）。`AVAssetWriterInputPixelBufferAdaptor` のプールから `CVPixelBuffer` を取得し再利用。
- ループ内は `autoreleasepool { ... }` で囲み、`CMSampleBuffer` や `CIImage` のライフタイムを短縮。
- 音声は `AVAssetReaderAudioMixOutput` → `AVAssetWriterInput` で無変換コピー（タイムスタンプはビデオ進行に従い順次投入）。
- 進捗は `sampleTime.seconds / duration.seconds`。ETA は移動平均のスループットで近似。
- 失敗時は即座にライター/リーダーを停止し、`onVideoError` 通知後クリーンアップ。

### エンコード設定
- 既定: H.264 (`AVVideoCodecType.h264`), コンテナ: `.mp4`
- HEVC: iOS サポート時オプション（4K など高解像度向け）
- ビットレート: 指定が無ければ解像度係数・FPS から目安を算出（例: `bitsPerPixel * width * height * fps`）
- フレームレート制限: `maxFps` を指定時、タイムスタンプ間引き
- リサイズ: `maxLongSide` を指定時、`CILanczosScaleTransform` を適用（オーバーレイ位置はスケール後基準）

## パフォーマンス最適化
- Metal バックエンドの `CIContext` をシングルトンで再利用
- オーバーレイ画像とアフィン変換を事前計算（フレーム内でスケール計算しない）
- `AVAssetWriterInputPixelBufferAdaptor` のプールで `CVPixelBuffer` 再利用
- バックプレッシャー制御: `writerInput.isReadyForMoreMediaData` をポーリングしながら投入
- GCD QoS: `.userInitiated`。I/O はシリアルに、デコード/合成/エンコードは内部パイプで並列度 1〜2 を維持（過剰並列は逆効果）

## エラーハンドリング/キャンセル
- 代表的コード: `decode_failed` / `encode_failed` / `compose_failed` / `io_failed` / `cancelled`
- `cancel(taskId)` 呼び出しで Reader/Writer を停止、出力の中間ファイルを削除
- 例外は `onVideoError` と Host API の失敗で両方通知（片方のみにならないよう調整）

## 互換性/後方互換
- 既存の画像 API に変更はない
- 新規 API は Pigeon を介して追加（Dart クライアントはメソッド増設）
- iOS 未対応の Android ではメソッド呼び出しで `MissingPluginException` を明示（README に記載）

## テスト計画
- Dart ユニット: Pigeon チャネル経路のシェイプ検証（既存 `compose_text_test.dart` と同様にモック）
- iOS ユニット/統合: 2〜3 秒の 720p テスト動画に対し、
  - アンカーごとのピクセル検査（角の数ピクセルの色を期待値で比較）
  - 進捗が単調増加し 1.0 で完結
  - キャンセル時に中間ファイルが削除される
- 実時間ベンチ: 1080p/30fps/5s でリアルタイムの 1.5〜3.0x を目標（端末依存）。

## 実装タスク（順序）
1. Pigeon スキーマ拡張（Video リクエスト/レスポンス/コールバック/キャンセル）
2. `dart run pigeon` でコード生成（Dart/Swift）
3. Dart クライアント API 追加（ハンドル/Stream 橋渡し）
4. iOS: `VideoWatermarkProcessor.swift` 実装（Reader/Writer/CI 合成）
5. iOS: `WatermarkApiImpl` に `composeVideo` と `cancel` を追加、コールバックセットアップ
6. 例外・エラーコードの共通化
7. Example アプリに動画デモ UI 追加（入力選択、進捗、キャンセル）
8. README/CHANGELOG 更新、初期 E2E 動作確認

## 既知のリスク
- HEVC は端末/OS によりエンコード可否/再生互換に差。既定は H.264。
- カラースペース/色域（BT.601/709）は入力に依存。`CIContext` は sRGB。厳密な色一致が必要なら YUV パスへの対応検討が必要。
- 回転（`preferredTransform`）の扱いは端末差があるため、端末/動画での回帰テスト必須。

## 将来拡張
- 複数レイヤー/アニメーション/時間範囲指定
- GPU 専用カスタム `AVVideoCompositing` 実装
- Android 実装（MediaCodec/MediaMuxer + OpenGL/SurfaceTexture）

---
この設計に問題なければ、Pigeon スキーマ拡張と iOS 側 `VideoWatermarkProcessor.swift` のスキャフォールドから着手します。
