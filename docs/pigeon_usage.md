# Pigeon の使い方とディレクトリ構成（Subject Lift Kit）

このドキュメントは、本リポジトリにおける Pigeon の利用方法を、ディレクトリ構成を中心にまとめたものです。別プロジェクトへ展開する際の雛形としても参照できます。

## 目的と全体像
- Flutter（Dart）と iOS（Swift）の間で型安全なメッセージ通信を行うために Pigeon を使用します。
- 仕様（API・データ型）は `pigeons/messages.dart` に集約し、コマンドで Dart/Swift の生成物を再生成します。
- 生成物は Dart 側が `lib/gen/`、iOS 側が `ios/Classes/` に配置されます（どちらも自動生成ファイルで手動編集しません）。

## ディレクトリ構成（Pigeon 周辺）
- `pigeons/`
  - `messages.dart`: Pigeon の単一ソース（API/データ型の定義）。`@ConfigurePigeon` で生成先を指定。
- `lib/`
  - `subject_lift_kit.dart`: 公開 Dart API。生成物を利用して Flutter からホスト API を呼び出します。
  - `gen/messages.g.dart`: Pigeon 生成（Dart）。メッセージのシリアライズ、`SubjectLiftApi` クライアント等。
- `ios/Classes/`
  - `SubjectLiftKitPlugin.swift`: iOS 側の実装。生成されたセットアップに自前実装を登録します。
  - `Messages.g.swift`: Pigeon 生成（Swift）。メッセージのコーデック、`SubjectLiftApi` プロトコル等。
- `example/`
  - サンプルアプリとテスト。生成物と公開 API の利用例として動作確認に使用。

> 生成ファイル（`lib/gen/*.dart` と `ios/Classes/Messages.g.swift`）は編集禁止。仕様変更は必ず `pigeons/messages.dart` を更新して再生成します。

## 定義ファイル（pigeons/messages.dart）
本リポジトリでは `@ConfigurePigeon` で生成先を明示しています（抜粋）。

```dart
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: "subject_lift_kit",
    dartOut: 'lib/gen/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'ios/Classes/Messages.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
@HostApi()
abstract class SubjectLiftApi {
  @async
  SegmentationResult extractForeground(ImageData imageData);
}
```

- `dartOut` / `swiftOut` で生成ファイルのパスを固定しています。
- API は `@HostApi` で宣言し、引数・戻り値はプリミティブ（`int`/`double`/`bool`/`String`/`Uint8List`）、List/Map、または Pigeon のデータクラスを使用します。

## 生成物が担う役割
- `lib/gen/messages.g.dart`
  - Flutter 側からホスト（iOS）へ送るための `SubjectLiftApi` クライアントと、エンコード/デコード処理を提供。
- `ios/Classes/Messages.g.swift`
  - iOS 側で受け取るための `SubjectLiftApi` プロトコルと、チャネルセットアップ用の `SubjectLiftApiSetup`、コーデック等を提供。

## iOS 実装との接続ポイント
- `ios/Classes/SubjectLiftKitPlugin.swift` 内で、生成物の `SubjectLiftApiSetup.setUp(...)` に自前実装（`SubjectLiftApi` 準拠のクラス）を登録します。
- 本リポジトリでは `SubjectLiftApiImpl` が `extractForeground(...)` を実装し、Vision Framework で前景抽出を行います。

## Flutter 側の呼び出し
- `lib/subject_lift_kit.dart` から `SubjectLiftApi`（生成物）を利用します。
- 例：`SubjectLiftKit.extractForeground(imageBytes)` が内部で `ImageData` を組み立て、生成クライアント経由で iOS 実装を呼び出します。

## 再生成手順（コマンド）
- 依存取得: `flutter pub get`
- 生成: `dart run pigeon --input pigeons/messages.dart`
- フォーマット（任意）: `dart format .`
- 静的解析（推奨）: `flutter analyze`

> ディレクトリが無い場合は `mkdir -p lib/gen ios/Classes` を事前に実行してください。

## 変更フロー（仕様変更時の手順）
1. `pigeons/messages.dart` を編集（API 追加/型変更）。
2. `dart run pigeon --input pigeons/messages.dart` で再生成。
3. iOS 側（`SubjectLiftApi` 準拠クラス）に新メソッドの実装を追加。
4. Dart の呼び出しコード（必要なら公開 API）を更新。
5. `example/` で動作確認とテスト。

## 他プロジェクトへ展開する際の指針
- 最低限用意するもの
  - `pigeons/messages.dart`（仕様の単一ソース）
  - `lib/gen/`（Dart 生成物の置き場）
  - `ios/Classes/`（Swift 生成物とプラグイン実装の置き場）
  - `pubspec.yaml` の `dev_dependencies` に `pigeon` を追加
- 手順の雛形
  1. `pigeons/messages.dart` を作成し、`@ConfigurePigeon` で `dartOut`/`swiftOut` を自プロジェクトのパスへ設定。
  2. `@HostApi` にメソッドを定義、必要なデータクラスを宣言。
  3. `dart run pigeon --input pigeons/messages.dart` で生成。
  4. iOS 側に `SubjectLiftApi` 準拠の実装を作り、`SubjectLiftApiSetup.setUp` で登録。
  5. Dart 側は `lib/gen/...` のクライアントを呼び出すラッパー（公開 API）を用意。
  6. `example/` などで実際の利用フローをテスト。

## ベストプラクティス / 注意点
- 生成物を直接編集しない（再生成で上書きされます）。
- API 変更は Dart/Swift の両方へ影響するため、必ず iOS 実装と Dart 呼び出しの両方を更新。
- `Uint8List` などバイナリデータを扱う場合、サイズが大きいとメッセージ越しにコストがかかる点に注意。
- Pigeon のバージョンを `pubspec.yaml` で固定し、チーム・CI で揃えると差分が安定します。
- iOS 固有機能の場合、Simulator 非対応・OS バージョン条件（本リポジトリは iOS 17+）を明記しておく。

## リンク（リポジトリ内）
- 定義: `pigeons/messages.dart`
- Dart 生成: `lib/gen/messages.g.dart`
- Swift 生成: `ios/Classes/Messages.g.swift`
- iOS 実装: `ios/Classes/SubjectLiftKitPlugin.swift`
- 公開 API: `lib/subject_lift_kit.dart`
- サンプル: `example/`

## よくあるトラブルシュート
- 生成ファイルが見つからない/ビルド失敗
  - 生成前に `lib/gen` と `ios/Classes` が存在するか確認。
  - `dart run pigeon --input pigeons/messages.dart` を再実行。
- 実装が呼ばれない
  - `register(with:)` で `SubjectLiftApiSetup.setUp` が呼ばれているか確認。
- API を増やしたのにクラッシュする/型不一致
  - Dart/Swift 双方のシグネチャが一致しているか、Optional/Non-null の扱いを再確認。

---
このドキュメントは `subject_lift_kit` の構成に合わせていますが、`@ConfigurePigeon` の出力先やパッケージ名を変更すれば、同じ設計を他プロジェクトでも再利用できます。
