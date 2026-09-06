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
    @Published public private(set) var song: Song? {
        didSet {
            guard !isRestoringHistory, oldValue != song else { return }
            if editStart == nil, let oldValue {
                undoSongs.append(oldValue)
                if undoSongs.count > 100 { undoSongs.removeFirst() }
                redoSongs.removeAll()
            }
            refreshHistoryAvailability()
        }
    }
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false
    @Published public private(set) var historyRevision = 0
    private var undoSongs: [Song] = []
    private var redoSongs: [Song] = []
    private var editStart: Song?
    private var isRestoringHistory = false

    public func beginEdit() {
        endEdit()
        editStart = song
    }

    public func endEdit() {
        if let editStart, editStart != song {
            undoSongs.append(editStart)
            if undoSongs.count > 100 { undoSongs.removeFirst() }
            redoSongs.removeAll()
        }
        editStart = nil
        refreshHistoryAvailability()
    }

    private func refreshHistoryAvailability() {
        canUndo = !undoSongs.isEmpty || (editStart != nil && editStart != song)
        canRedo = !redoSongs.isEmpty && (editStart == nil || editStart == song)
    }

    public func undo() {
        endEdit()
        guard let previous = undoSongs.popLast(), let current = song else { return }
        redoSongs.append(current)
        restoreHistory(previous)
    }

    public func redo() {
        endEdit()
        guard let next = redoSongs.popLast(), let current = song else { return }
        undoSongs.append(current)
        restoreHistory(next)
    }

    private func restoreHistory(_ restored: Song) {
        audio.panic()
        isRestoringHistory = true
        song = restored
        title = restored.title
        if !restored.tracks.contains(where: { $0.id == selectedTrackID }) {
            selectedTrackID = restored.tracks.first?.id
        }
        isRestoringHistory = false
        try? rebuildPlayback(resetPosition: false)
        refreshHistoryAvailability()
        historyRevision += 1
    }
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
        return sequence?.tick(atSeconds: positionSeconds)
            ?? Int((positionSeconds * Double(song.tempoBPM) * Double(song.timeBase) / 60.0).rounded(.down))
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
        isRestoringHistory = true
        song = loaded
        isRestoringHistory = false
        editStart = nil
        undoSongs.removeAll()
        redoSongs.removeAll()
        refreshHistoryAvailability()
        historyRevision += 1
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

    public func replaceEvents(trackID: Int, in range: Range<Int>, with events: [TrackEvent]) {
        guard let index = song?.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        endEdit()
        song?.tracks[index].replaceEvents(in: range, with: events)
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
        endEdit()
        song?.tracks[trackIndex].updateAttributes(
            midiChannel: midiChannel,
            startTick: startTick,
            keyShift: keyShift,
            memo: memo
        )
        try? rebuildPlayback(resetPosition: false)
    }

    public func updateSongSettings(title: String, tempoBPM: Int, numerator: Int, denominator: Int) {
        guard var edited = song else { return }
        endEdit()
        let tick = positionTick
        edited.title = String(title.prefix(64))
        edited.tempoBPM = min(255, max(1, tempoBPM))
        edited.beatNumerator = min(32, max(1, numerator))
        edited.beatDenominator = [1, 2, 4, 8, 16, 32].contains(denominator) ? denominator : 4
        song = edited
        self.title = edited.title
        try? rebuildPlayback(resetPosition: false)
        positionSeconds = sequence?.seconds(atTick: tick) ?? 0
        pausedAt = positionSeconds
        if state == .playing { runtime.play(from: positionSeconds) }
    }

    public var canAddTrack: Bool { (song?.tracks.count ?? 36) < 36 }

    @discardableResult
    public func addTrack(copying sourceID: Int? = nil) -> Int? {
        guard var edited = song, canAddTrack else { return nil }
        endEdit()
        let id = (edited.tracks.map(\.id).max() ?? -1) + 1
        let usedNumbers = Set(edited.tracks.map(\.number))
        let number = (1...36).first { !usedNumbers.contains($0) } ?? edited.tracks.count + 1
        var track = sourceID.flatMap { source in edited.tracks.first { $0.id == source } }
            ?? Track(id: id, number: number, midiChannel: (number - 1) % 16 + 1,
                     events: [TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)])
        track.id = id
        track.number = number
        track.memo = sourceID == nil ? "Track \(number)" : String((track.memo + " copy").prefix(36))
        edited.tracks.append(track)
        song = edited
        selectedTrackID = id
        try? rebuildPlayback(resetPosition: false)
        return id
    }

    public func deleteTrack(id: Int) {
        guard var edited = song, edited.tracks.count > 1,
              let index = edited.tracks.firstIndex(where: { $0.id == id }) else { return }
        endEdit()
        edited.tracks.remove(at: index)
        song = edited
        if selectedTrackID == id { selectedTrackID = edited.tracks[min(index, edited.tracks.count - 1)].id }
        audio.panic()
        try? rebuildPlayback(resetPosition: false)
    }

    public func play(fromMeasure measure: Int? = nil) async throws {
        guard sequence != nil else { return }
        if !audio.isAttached {
            try await ensureAudio()
        } else if !audio.engine.isRunning {
            try audio.start()
        }
        audioErrorMessage = nil
        if let start = PlaybackStart.seconds(
            fromMeasure: measure,
            isPaused: state == .paused,
            song: song,
            sequence: sequence
        ) {
            pausedAt = start
        }
        if state == .playing {
            audio.panic()
        }
        positionSeconds = pausedAt
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

enum PlaybackStart {
    static func seconds(fromMeasure measure: Int?, isPaused: Bool, song: Song?, sequence: RCPSequence? = nil) -> Double? {
        if let measure, let song {
            let tick = song.startTick(ofMeasure: measure)
            return sequence?.seconds(atTick: tick) ?? song.seconds(atTick: tick)
        }
        if isPaused {
            return nil
        }
        return 0
    }
}
