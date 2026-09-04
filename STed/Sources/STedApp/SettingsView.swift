import SwiftUI
import UniformTypeIdentifiers
import STedPlayback

struct SettingsView: View {
    @EnvironmentObject private var engine: PlaybackEngine
    @State private var isImporterPresented = false

    var body: some View {
        Form {
            Section("曲") {
                LabeledContent("タイトル", value: engine.title.isEmpty ? "—" : engine.title)
                if let song = engine.song {
                    LabeledContent("テンポ", value: "\(song.tempoBPM)")
                    LabeledContent("タイムベース", value: "\(song.timeBase)")
                    LabeledContent("拍子", value: "\(song.beatNumerator)/\(song.beatDenominator)")
                    LabeledContent("トラック数", value: "\(song.tracks.count)")
                } else {
                    Text("まだ曲が読み込まれていません")
                        .foregroundStyle(.secondary)
                }
            }

            Section("ファイル") {
                Button("RCP を開く") { isImporterPresented = true }
                Button("Demo Phrase を読み込む") { loadDemo() }
            }

            Section("音源") {
                LabeledContent("出力", value: engine.instrumentName)
                Text("aumu / Sc55 / Rin2（SC-55 AUv3）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("MIDI") {
                LabeledContent("ハードウェア MIDI", value: "未接続")
                Text("CoreMIDI の入出力は後で同じ MIDI 出口に足す。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("表示") {
                LabeledContent("iPhone", value: "ポートレート固定")
                LabeledContent("iPad / Mac", value: "トラック一覧 + 編集の分割")
            }
        }
        .navigationTitle("設定")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try engine.load(url: url)
                } catch {
                    engine.reportError(error)
                }
            case .failure(let error):
                engine.reportError(error)
            }
        }
    }

    private func loadDemo() {
        do {
            try engine.loadDemo()
        } catch {
            engine.reportError(error)
        }
    }
}
