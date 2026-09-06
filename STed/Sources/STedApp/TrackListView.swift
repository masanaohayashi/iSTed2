import SwiftUI
import STedCore
import STedPlayback

struct TrackListView: View {
    @EnvironmentObject private var engine: PlaybackEngine
    var opensEditorInStack: Bool
    @Binding var isSettingsPresented: Bool

    @State private var isSongSettingsPresented = false
    @State private var trackToEdit: Track?

    var body: some View {
        List {
            Section {
                songHeader
                TransportBar()
                if let errorMessage = engine.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                if let audioErrorMessage = engine.audioErrorMessage {
                    Text(audioErrorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("トラック") {
                if engine.song != nil {
                    Button {
                        if let id = engine.addTrack() {
                            trackToEdit = engine.song?.tracks.first { $0.id == id }
                        }
                    } label: { Label("トラック追加", systemImage: "plus") }
                    .disabled(!engine.canAddTrack)
                }
                if let tracks = engine.song?.tracks, !tracks.isEmpty {
                    ForEach(tracks) { track in
                        trackRow(track)
                    }
                } else {
                    Text("新規プロジェクトを作成するか RCP を開く")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(engine.title.isEmpty ? "STed" : engine.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("新規") { engine.requestFileOperation(.newProject) }
            }
            ToolbarItem(placement: .primaryAction) {
                settingsButton
            }
            ToolbarItem(placement: .automatic) {
                Button("開く") { engine.requestFileOperation(.open) }
            }
            ToolbarItem(placement: .automatic) {
                Button("保存") { engine.requestFileOperation(.save) }
                    .disabled(engine.song == nil)
            }
            ToolbarItem(placement: .automatic) {
                Button("名前を付けて保存") { engine.requestFileOperation(.saveAs) }
                    .disabled(engine.song == nil)
            }
        }
        .sheet(isPresented: $isSongSettingsPresented) {
            if let song = engine.song {
                SongSettingsView(song: song) { title, tempo, numerator, denominator in
                    engine.updateSongSettings(title: title, tempoBPM: tempo, numerator: numerator, denominator: denominator)
                }
            }
        }
        .sheet(item: $trackToEdit) { track in
            TrackSettingsView(track: track) { channel, start, shift, name in
                engine.updateTrack(trackID: track.id, midiChannel: channel, startTick: start, keyShift: shift, memo: name)
            }
        }
    }

    private var songHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let song = engine.song {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button { isSongSettingsPresented = true } label: {
                            labeled("TEMPO", "\(song.tempoBPM)")
                        }
                        .buttonStyle(.plain)
                        labeled("TBASE", "\(song.timeBase)")
                        labeled("BEAT", "\(song.beatNumerator)/\(song.beatDenominator)")
                    }
                    HStack {
                        labeled("MEAS", "\(engine.positionTime.measure)")
                        labeled("STEP", "\(engine.positionTime.step)")
                        Text(engine.state.label)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.monospacedDigit())
                Button("曲設定…") { isSongSettingsPresented = true }
                    .buttonStyle(.borderless)
                ProgressView(
                    value: engine.songEndSeconds == 0
                        ? 0
                        : min(1, engine.positionSeconds / engine.songEndSeconds)
                )
            } else {
                Text("曲が読み込まれていません")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func trackRow(_ track: Track) -> some View {
        let row = HStack {
            Text("\(track.number)")
                .frame(width: 28, alignment: .leading)
                .font(.body.monospacedDigit())
            Button(track.mode.isMuted ? "MUTE" : "PLAY") {
                engine.setMuted(!track.mode.isMuted, trackID: track.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text(track.midiChannel.map { "Ch\($0)" } ?? "OFF")
                .frame(width: 44, alignment: .leading)
                .font(.caption.monospacedDigit())
            VStack(alignment: .leading, spacing: 2) {
                Text(track.memo.isEmpty ? "Track \(track.number)" : track.memo)
                    .lineLimit(1)
                Text("ST+ \(track.startTick)  K#+ \(track.keyShift)  \(track.stepCount) step")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("トラック設定…") { trackToEdit = track }
                Button("複製") { _ = engine.addTrack(copying: track.id) }
                    .disabled(!engine.canAddTrack)
                Button("トラック削除", role: .destructive) { engine.deleteTrack(id: track.id) }
                    .disabled((engine.song?.tracks.count ?? 0) <= 1)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("トラック \(track.number) の操作")
        }
        .contentShape(Rectangle())

        if opensEditorInStack {
            NavigationLink(value: AppRoute.trackEditor(track.id)) {
                row
            }
        } else {
            row
                .listRowBackground(
                    engine.selectedTrackID == track.id
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .onTapGesture {
                    engine.selectedTrackID = track.id
                }
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if opensEditorInStack {
            NavigationLink(value: AppRoute.settings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("設定")
        } else {
            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("設定")
        }
    }

    private func labeled(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(.secondary)
            Text(value)
        }
    }

}

private struct SongSettingsView: View {
    @State private var title: String
    @State private var tempo: Int
    @State private var numerator: Int
    @State private var denominator: Int
    @Environment(\.dismiss) private var dismiss
    var onSave: (String, Int, Int, Int) -> Void

    init(song: Song, onSave: @escaping (String, Int, Int, Int) -> Void) {
        _title = State(initialValue: song.title)
        _tempo = State(initialValue: song.tempoBPM)
        _numerator = State(initialValue: song.beatNumerator)
        _denominator = State(initialValue: song.beatDenominator)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("曲名", text: $title)
                TextField("テンポ（BPM）", value: $tempo, format: .number)
                Stepper("テンポ: \(tempo) BPM", value: $tempo, in: 1...255)
                Stepper("拍子の分子: \(numerator)", value: $numerator, in: 1...32)
                Picker("拍子の分母", selection: $denominator) {
                    ForEach([1, 2, 4, 8, 16, 32], id: \.self) { Text("\($0)").tag($0) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("曲設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        onSave(title, tempo, numerator, denominator)
                        dismiss()
                    }
                    .disabled(!(1...255).contains(tempo))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
