# STed2.07m Swift／Xcode 移植方針（初版）

## 1. 方針の前提

- 対象プラットフォームは macOS と iOS（iPhone／iPad）。
- 実装言語は Swift。開発・配布単位は Xcode プロジェクトまたは Xcode ワークスペースとする。
- AudioUnit 経路を最優先し、ハードウェア MIDI は後から追加できるアダプタとして扱う。
- 既存の JUCE/C++ コードを直接移植するのではなく、RCP プレイヤーの仕様・変換結果・リアルタイム処理の設計を参照して Swift で再実装する。

参照実装：

`/Users/ring2/Documents/src/Nuked-SC55-jcmoyer/Plugins`

## 2. 参照実装から確認できた再利用境界

### 2.1 RCP プレイヤーの入力と出力

参照実装の `Source/RcpFilePlayer.h` では、RCP v2 のバイト列を読み込み、共通の MIDI ファイルデータへ展開する API が独立している。

入力は RCP ファイル全体、出力は次のような時刻付きイベント列である。

```text
Timed MIDI event = { playback time in seconds, raw MIDI bytes }
```

この設計は STed の編集モデルと AudioUnit の再生実装の間に置く中間形式として適している。ただし、STed 本体の編集・保存では、元の 4 バイトイベント列と RCP ヘッダ情報を失わない別のドメインモデルが必要になる。

### 2.2 参照実装が扱う RCP の挙動

- RCP v2 ヘッダと最大 36 トラックを読み込む。
- トラックのミュート、MIDI チャンネル、移調、開始オフセットを反映する。
- 通常ノートを MIDI ノートオン／ノートオフへ展開する。
- ユーザー・エクスクルーシブ、トラック・エクスクルーシブ、Roland／Yamaha／MKS-7 系イベントを MIDI バイト列へ変換する。
- テンポ変更、テンポグラデーション、拍子を時間軸へ反映する。
- repeat、SAME MEAS、コメント、継続レコードなどを展開する。
- 同一時刻のイベント順を保持する。CC の選択→データエントリや、ノートオン／オフの順序を並べ替えない。
- 不正な長さ、再帰・展開過多、時刻オーバーフロー、イベント数過多をエラーとして検出する。
- 付属 `.WRD` を楽曲とは別の表示データとして任意に読み込む。

### 2.3 参照実装のリアルタイム境界

`Source/PluginProcessor.cpp` では、次の責務分離が行われている。

- ファイル読み込みと解析はオーディオコールバックの外で行う。
- 解析済みファイルは不変データとして公開する。
- オーディオ側は再生位置と次イベント番号だけを保持する。
- ホストからの MIDI とファイル再生イベントをサンプル位置順に送出する。
- 大きなオーディオブロックでイベントが粗くならないよう、約 1 ms 単位の小区間でイベントを確認する。
- 停止・一時停止・曲の差し替え時には、全ノートオフとコントローラリセットを送る。
- オーディオスレッドでは、ファイル解析、文字列変換、画面描画、通常の動的メモリ確保を行わない。

この境界は Swift 版でも維持する。ただし、最終的な送出単位は AudioUnit の種類と接続方法を決めた後に確定する。

## 3. 推奨 Xcode 構成

```text
STed.xcworkspace
├─ STedCore                 Swift Package / Framework
│  ├─ RCPCodec              RCP/R36 の読み書き
│  ├─ STedModel             楽曲・トラック・イベント
│  ├─ RCPInterpreter        repeat／SAME MEAS／特殊イベント展開
│  ├─ MIDIEventModel        型付き MIDI と raw MIDI
│  └─ DefinitionCodec       DEF/RAS/REX 等
├─ STedPlayback             共通再生モデル
│  ├─ PlaybackClock
│  ├─ EventScheduler
│  └─ AudioUnitAdapter
├─ STedApp                  macOS／iOS の SwiftUI アプリ
├─ STedAudioUnit             必要になった時点で追加する AUv3 ターゲット
└─ STedTests                 XCTest、RCP fixture、再生イベント比較
```

`STedCore` は Foundation を中心にし、UI、AudioUnit、ハードウェア MIDI、ファイル選択 UI から依存されない形にする。

### 3.1 ドメインモデルの基本形

```swift
struct Song {
    var header: SongHeader
    var tracks: [Track]          // 最大 36
    var definitions: DefinitionSet
}

struct Track {
    var settings: TrackSettings
    var events: [STedEvent]
}

struct TimedMIDIEvent {
    var time: MusicTime
    var bytes: [UInt8]
}
```

`TimedMIDIEvent` は再生用の展開結果であり、編集・保存の唯一の正規表現にはしない。保存時に RCP/R36 の特殊イベントや圧縮表現を再現できるよう、`STedEvent` は note、controller、exclusive、repeat、same-measure 等を区別する。

## 4. AudioUnit 優先の再生方針

「AudioUnit 対応」が次のどちらを意味するかで、Xcode ターゲットは変わる。

1. STed アプリが AudioUnit 音源をホストして、RCP を演奏する。
2. STed 自体が AUv3 プレイヤー／音源としてホストアプリに読み込まれる。

初期実装では、共通の `STedPlayback` から切り離した `AudioUnitAdapter` を作り、どちらの形にも展開できるようにする。既存の Nuked-SC55 プロジェクトは AUv3 と Standalone の両方を生成しているが、STed の最初の検証対象は「RCP を読み込み、AudioUnit の音源へ正しいイベントを届けること」とする。

### 4.1 再生パイプライン

```text
RCP/R36 bytes
    ↓ 解析（非リアルタイム）
Song / STedEvent
    ↓ 展開（非リアルタイム）
TimedMIDIEvent[]（時刻・順序を確定）
    ↓ 再生時計
AudioUnitAdapter
    ↓
AudioUnit 音源 → オーディオ出力
```

### 4.2 必須のリアルタイム契約

- 再生開始前に全イベントと必要な音源初期化データを準備する。
- オーディオ処理中に Swift の配列拡張、ファイル I/O、ロック待ち、ログ出力を行わない。
- 曲の差し替えは、UI／ワーカースレッドで新しい不変スナップショットを作ってから再生側へ公開する。
- 再生位置はオーディオ時計を正とし、UI はスカラー値を購読する。
- 同一時刻イベントは元の順序を保持する。
- 停止・一時停止・割り込み時に発音中ノートを解放する。
- AudioUnit の未接続、初期化失敗、非対応イベントを UI に返せるエラー型を用意する。

## 5. 実装フェーズ

### Phase 0：互換性フィクスチャの準備

- `STed2.07m` と参照実装で利用できる RCP/R36 サンプルを集める。
- ヘッダ、空トラック、和音、テンポ変更、repeat、SAME MEAS、CC、SysEx、36 トラックを含む最小 fixture を作る。
- 参照実装の出力イベント列をゴールデンデータ化する。

### Phase 1：Swift RCP コア

- RCP v2／R36 読み込み。
- 4 バイトイベントのデコードと検証。
- テンポ・拍子・タイムベースから MusicTime への変換。
- 特殊イベント、繰り返し、SAME MEAS の展開。
- 参照実装とのイベントバイト列・順序・時刻比較。

### Phase 2：AudioUnit 再生スパイク

- 1 トラックのノートオン／ノートオフから開始。
- AudioUnit へ送るイベントの時刻精度を確認。
- 主要 CC、プログラムチェンジ、ピッチベンド、SysEx を追加。
- 曲の停止、再開、差し替え、オーディオ割り込みを確認。

### Phase 3：SwiftUI アプリの最小版

- macOS／iOS 共通のファイル読み込み。
- タイトル、テンポ、36 トラック一覧。
- Load、Play、Pause、Stop。
- 再生位置とエラー表示。

### Phase 4：STed 編集機能

- トラック属性。
- ノート編集、範囲操作、クオンタイズ、コピー／ミックス。
- 楽譜表示、コントローラ表示。
- RCP/R36 保存。

### Phase 5：録音と互換拡張

- AudioUnit 経路からの MIDI 入力またはアプリ内鍵盤。
- リアルタイム録音、ステップ入力。
- DEF、RAS、REX、RES、CM6、GSD。
- ハードウェア MIDI アダプタ。

## 6. 参照実装との差分として注意する点

- 参照実装は C++／JUCE であり、Swift の値型・配列・Actor・`AudioUnit` のスレッド契約へそのまま置き換えられない。
- 参照実装の `MidiFileData` は再生に便利なフラット形式だが、STed の完全な編集・再保存には情報が不足する可能性がある。
- 参照実装は Nuked SC-55 エミュレータを最終音源としている。STed の AudioUnit 対応では、音源固有の制御データを汎用 MIDI、AudioUnit パラメータ、または音源固有 SysEx のどれで扱うかを定義する必要がある。
- 既存プロジェクトには生成済み Xcode ファイルや作業中の変更があるため、STed 側へは必要な仕様とテストデータだけを参照し、ファイルを直接改変・コピーしない。

## 7. 最初の完了条件

最初のマイルストーンは、編集画面の完全再現ではなく、次を満たすこととする。

- Xcode から macOS と iOS の共通コアをビルドできる。
- 同じ RCP fixture を読み込んだとき、参照実装と Swift 実装で主要 MIDI イベントのバイト列と順序が一致する。
- AudioUnit 音源へ、ノート、主要 CC、プログラムチェンジ、ピッチベンド、テンポを正しい時刻で送出できる。
- Stop／Pause／差し替え後にノートが取り残されない。
- RCP の不正データや未対応イベントを、クラッシュではなく診断可能なエラーとして返す。

## 8. 次に決める一点

実装開始前に、AudioUnit 対応の第一形態を次のどちらにするか決める必要がある。

- **A：STed が AudioUnit 音源をホストする macOS/iOS アプリ**
- **B：STed 自体が RCP を演奏する AUv3 プレイヤー**

コア、RCP 解析、イベント展開は共通化できるが、Xcode ターゲット、ファイル選択、再生時計、ホストとの状態保存の設計が変わる。既存の RCP プレイヤーを最も直接的に活かすのは B、STed を作曲・編集アプリとして自然に使うのは A である。

