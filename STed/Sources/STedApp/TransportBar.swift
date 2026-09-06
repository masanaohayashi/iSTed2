import SwiftUI
import STedPlayback

struct TransportBar: View {
    @EnvironmentObject private var engine: PlaybackEngine
    @Environment(\.horizontalSizeClass) private var sizeClass
    var compact: Bool = false
    var playMeasure: Int? = nil

    private var isCompact: Bool {
        compact || sizeClass == .compact
    }

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Button("Play", action: play)
                .disabled(engine.state == .empty || engine.state == .playing)
            Button("Pause", action: engine.pause)
                .disabled(engine.state != .playing)
            Button("Stop", action: engine.stop)
                .disabled(engine.state == .empty)
            if !isCompact, let song = engine.song {
                Spacer()
                Text("MEAS \(engine.positionTime.measure)  STEP \(engine.positionTime.step)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(song.tempoBPM) BPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(isCompact ? .small : .regular)
    }

    private func play() {
        Task {
            do {
                try await engine.play(fromMeasure: playMeasure)
            } catch {
                engine.reportAudioError(error)
            }
        }
    }
}

extension PlaybackEngine.State {
    var label: String {
        switch self {
        case .empty: "Empty"
        case .loaded: "Loaded"
        case .playing: "Playing"
        case .paused: "Paused"
        }
    }
}
