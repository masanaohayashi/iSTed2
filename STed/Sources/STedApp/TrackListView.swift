import SwiftUI
import UniformTypeIdentifiers
import STedCore
import STedPlayback

struct TrackListView: View {
    @EnvironmentObject private var engine: PlaybackEngine
    var opensEditorInStack: Bool
    @Binding var isSettingsPresented: Bool

    @State private var isImporterPresented = false

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
                if let tracks = engine.song?.tracks, !tracks.isEmpty {
                    ForEach(tracks) { track in
                        trackRow(track)
                    }
                } else {
                    Text("RCP を開くか Demo を読み込む")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(engine.title.isEmpty ? "STed" : engine.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                settingsButton
            }
            ToolbarItem(placement: .automatic) {
                Button("Open RCP") { isImporterPresented = true }
            }
            ToolbarItem(placement: .automatic) {
                Button("Demo") { loadDemo() }
            }
        }
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

    private var songHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let song = engine.song {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        labeled("TEMPO", "\(song.tempoBPM)")
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

    private func loadDemo() {
        do {
            try engine.loadDemo()
        } catch {
            engine.reportError(error)
        }
    }
}
