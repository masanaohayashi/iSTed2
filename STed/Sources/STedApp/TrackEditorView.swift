import SwiftUI
import STedCore
import STedPlayback

struct TrackEditorView: View {
    @EnvironmentObject private var engine: PlaybackEngine
    let trackID: Int

    private var track: Track? {
        engine.song?.tracks.first { $0.id == trackID }
    }

    var body: some View {
        Group {
            if let song = engine.song, let track {
                let rows = track.eventRows(
                    timeBase: song.timeBase,
                    beatNumerator: song.beatNumerator,
                    beatDenominator: song.beatDenominator
                )
                List {
                    Section {
                        header(track)
                        TransportBar(compact: true)
                    }
                    Section("イベント") {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(String(format: "%3d:%03d", row.time.measure, row.time.step))
                                    .font(.body.monospacedDigit())
                                    .frame(width: 72, alignment: .leading)
                                Text(row.label)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("ST \(row.st)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 56, alignment: .trailing)
                                Text("GT \(row.gt)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 56, alignment: .trailing)
                                Text("V \(row.vel)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 48, alignment: .trailing)
                            }
                            .listRowBackground(
                                row.time.tick <= engine.positionTick
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView(
                    "トラックがありません",
                    systemImage: "minus.circle",
                    description: Text("先に曲を読み込む")
                )
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let track {
                    Button(track.mode.isMuted ? "MUTE" : "PLAY") {
                        engine.setMuted(!track.mode.isMuted, trackID: track.id)
                    }
                }
            }
        }
        .onAppear {
            engine.selectedTrackID = trackID
        }
    }

    private var title: String {
        if let track {
            let memo = track.memo.isEmpty ? "" : "  \(track.memo)"
            return "Track \(track.number)\(memo)"
        }
        return "トラック編集"
    }

    private func header(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                labeled("Ch", track.midiChannel.map(String.init) ?? "OFF")
                labeled("ST+", "\(track.startTick)")
                labeled("K#+", "\(track.keyShift)")
                labeled("Step", "\(track.stepCount)")
            }
            .font(.caption.monospacedDigit())
            Text("MEAS \(engine.positionTime.measure)   STEP \(engine.positionTime.step)")
                .font(.title3.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeled(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
