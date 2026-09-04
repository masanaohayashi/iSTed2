import Combine
import Foundation
import STedCore

@MainActor
public final class PlaybackEngine: ObservableObject {
    public enum State: Equatable {
        case empty
        case loaded
        case playing
        case paused
    }

    @Published public private(set) var state: State = .empty
    @Published public private(set) var positionSeconds: Double = 0
    @Published public private(set) var songEndSeconds: Double = 0
    @Published public private(set) var title: String = ""
    @Published public private(set) var song: Song?
    @Published public var selectedTrackID: Int?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var audioErrorMessage: String?

    public let audio = AudioUnitAdapter()
    private let runtime = PlaybackRuntime()
    private var sequence: RCPSequence?
    private var displayLink: Timer?
    private var pausedAt: Double = 0
    private var audioSetup: Task<Void, Error>?

    public var positionTime: MusicalTime {
        guard let song else {
            return MusicalTime(tick: 0, timeBase: 48, beatNumerator: 4, beatDenominator: 4)
        }
        return song.musicalTime(atTick: positionTick)
    }

    public var positionTick: Int {
        guard let song else { return 0 }
        return Int((positionSeconds * Double(song.tempoBPM) * Double(song.timeBase) / 60.0).rounded(.down))
    }

    public var selectedTrack: Track? {
        guard let selectedTrackID else { return nil }
        return song?.tracks.first { $0.id == selectedTrackID }
    }

    public init() {
        audio.clock = runtime
    }

    public func prepareAudio() async throws {
        try await ensureAudio()
        audioErrorMessage = nil
    }

    public var instrumentName: String {
        audio.instrumentName
    }

    public func reportError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    public func reportAudioError(_ error: Error) {
        audioErrorMessage = error.localizedDescription
    }

    public func load(data: Data, title: String = "") throws {
        stop()
        let loaded = try RCPDecoder.song(from: data)
        song = loaded
        selectedTrackID = loaded.tracks.first?.id
        self.title = loaded.title.isEmpty ? title : loaded.title
        try rebuildPlayback(resetPosition: true)
        state = .loaded
        errorMessage = nil
    }

    public func load(url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try load(data: Data(contentsOf: url), title: url.lastPathComponent)
    }

    public func loadDemo() throws {
        try load(data: RCPDemo.phrase, title: "Demo Phrase")
    }

    public func setMuted(_ muted: Bool, trackID: Int) {
        guard let index = song?.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        song?.tracks[index].mode = muted ? .mute : .play
        try? rebuildPlayback(resetPosition: false)
    }

    public func encodedRCP() throws -> Data {
        guard let song else { throw RCPError.noTracks }
        return RCPEncoder.encode(song)
    }

    public var exportFileName: String {
        let base = title.isEmpty ? "song" : title
        let cleaned = base.replacingOccurrences(of: "/", with: "-")
        return cleaned.hasSuffix(".rcp") || cleaned.hasSuffix(".RCP") ? cleaned : "\(cleaned).rcp"
    }

    public func updateEvent(trackID: Int, index: Int, _ event: TrackEvent) {
        guard let trackIndex = song?.tracks.firstIndex(where: { $0.id == trackID }),
              song?.tracks[trackIndex].events.indices.contains(index) == true
        else { return }
        song?.tracks[trackIndex].events[index] = event
        try? rebuildPlayback(resetPosition: false)
    }

    public func insertEvent(trackID: Int, at index: Int, _ event: TrackEvent = .defaultNote) {
        guard let trackIndex = song?.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        song?.tracks[trackIndex].insertEvent(event, at: index)
        try? rebuildPlayback(resetPosition: false)
    }

    @discardableResult
    public func insertNoteBefore(trackID: Int, at index: Int) -> TrackEvent? {
        guard let trackIndex = song?.tracks.firstIndex(where: { $0.id == trackID }) else { return nil }
        let insertedEvent = song?.tracks[trackIndex].insertNoteBefore(at: index)
        try? rebuildPlayback(resetPosition: false)
        return insertedEvent
    }

    public func deleteEvent(trackID: Int, at index: Int) {
        guard let trackIndex = song?.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        song?.tracks[trackIndex].deleteEvent(at: index)
        try? rebuildPlayback(resetPosition: false)
    }

    public func updateTrack(
        trackID: Int,
        midiChannel: Int?,
        startTick: Int,
        keyShift: Int,
        memo: String
    ) {
        guard let trackIndex = song?.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        song?.tracks[trackIndex].updateAttributes(
            midiChannel: midiChannel,
            startTick: startTick,
            keyShift: keyShift,
            memo: memo
        )
        try? rebuildPlayback(resetPosition: false)
    }

    public func play() async throws {
        guard sequence != nil else { return }
        if !audio.isAttached {
            try await ensureAudio()
        } else if !audio.engine.isRunning {
            try audio.start()
        }
        audioErrorMessage = nil
        if state != .paused {
            pausedAt = 0
        }
        runtime.play(from: pausedAt)
        state = .playing
        startClock()
    }

    private func ensureAudio() async throws {
        if audio.isAttached {
            try audio.start()
            return
        }
        if let audioSetup {
            try await audioSetup.value
            try audio.start()
            return
        }
        let setup = Task { @MainActor in
            try await audio.attachDefaultInstrument()
            try audio.start()
        }
        audioSetup = setup
        do {
            try await setup.value
        } catch {
            audioSetup = nil
            throw error
        }
    }

    public func pause() {
        guard state == .playing else { return }
        pausedAt = runtime.pause()
        audio.panic()
        stopClock()
        state = .paused
        positionSeconds = pausedAt
    }

    public func stop() {
        runtime.stop()
        audio.panic()
        stopClock()
        pausedAt = 0
        positionSeconds = 0
        if song != nil {
            state = .loaded
        } else {
            state = .empty
        }
    }

    private func rebuildPlayback(resetPosition: Bool) throws {
        guard let song else { return }
        do {
            let decoded = try song.playbackSequence()
            sequence = decoded
            songEndSeconds = decoded.songEndSeconds + decoded.lastBarSeconds
        } catch RCPError.noEvents {
            sequence = RCPSequence(
                timeBase: song.timeBase,
                tempoBPM: song.tempoBPM,
                beatNumerator: song.beatNumerator,
                beatDenominator: song.beatDenominator,
                events: []
            )
            songEndSeconds = 0
        }
        runtime.load(events: sequence?.events ?? [], songEnd: songEndSeconds)
        if resetPosition {
            positionSeconds = 0
            pausedAt = 0
        } else if state == .playing {
            runtime.play(from: positionSeconds)
        }
    }

    private func startClock() {
        stopClock()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        displayLink = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopClock() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        let snapshot = runtime.snapshot()
        positionSeconds = snapshot.position
        if snapshot.finished {
            stop()
        }
    }
}
