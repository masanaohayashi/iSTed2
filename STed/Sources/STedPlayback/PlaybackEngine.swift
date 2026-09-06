import Combine
import Foundation
import STedCore

public enum ProjectFileError: Error, LocalizedError, Equatable, Sendable {
    case noCurrentFile

    public var errorDescription: String? {
        switch self {
        case .noCurrentFile:
            return "保存先がまだ決まっていません。"
        }
    }
}

@MainActor
public final class PlaybackEngine: ObservableObject {
    public enum FileOperation: Equatable, Sendable {
        case newProject
        case open
        case save
        case saveAs
    }

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
    @Published public private(set) var currentFileURL: URL?
    @Published public private(set) var requestedFileOperation: FileOperation?
    @Published public private(set) var isDirty = false
    /// When enabled, track editors follow the current playback position.
    /// This belongs to the playback engine so every track shares one mode.
    @Published public private(set) var isChaseEnabled = false
    private var savedSong: Song?
    @Published public private(set) var song: Song? {
        didSet {
            if !isRestoringHistory, oldValue != song {
                if editStart == nil, let oldValue {
                    undoSongs.append(oldValue)
                    if undoSongs.count > 100 { undoSongs.removeFirst() }
                    redoSongs.removeAll()
                }
            }
            refreshDirtyState()
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

    public func cancelEdit() {
        guard let original = editStart else { return }
        editStart = nil
        restoreHistory(original)
    }

    private func refreshHistoryAvailability() {
        canUndo = !undoSongs.isEmpty || (editStart != nil && editStart != song)
        canRedo = !redoSongs.isEmpty && (editStart == nil || editStart == song)
    }

    private func refreshDirtyState() {
        isDirty = song != savedSong
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
    /// The most recently compiled editor snapshot. This may be newer than
    /// the plan currently being rendered while a live edit waits for a bar
    /// boundary.
    private var sequence: RCPSequence?
    private var latestPlaybackPlan: PlaybackPlan?
    private var playbackPlans: [Int: PlaybackPlan] = [:]
    private var playbackRevision = 0
    private var activePlanRevision = 0
    private var activeSequence: RCPSequence?
    private var activeTimelineOffset = 0.0
    private var playbackBuildTask: Task<Void, Never>?
    private var playbackBuildRequestID = 0
    private var playbackBuildPending = false
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
        let isRenderingPlan = state == .playing || state == .paused
        let currentSequence = isRenderingPlan ? (activeSequence ?? sequence) : sequence
        let offset = isRenderingPlan ? activeTimelineOffset : 0
        let sequenceSeconds = max(0, positionSeconds - offset)
        return currentSequence?.tick(atSeconds: sequenceSeconds)
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

    public func requestFileOperation(_ operation: FileOperation) {
        requestedFileOperation = operation
    }

    public func toggleChase() {
        isChaseEnabled.toggle()
    }

    public func consumeFileOperation() {
        requestedFileOperation = nil
    }

    public func load(data: Data, title: String = "") throws {
        try load(data: data, title: title, fileURL: nil)
    }

    private func load(data: Data, title: String, fileURL: URL?) throws {
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
        currentFileURL = fileURL
        savedSong = loaded
        refreshDirtyState()
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
        try load(data: Data(contentsOf: url), title: url.lastPathComponent, fileURL: url)
    }

    public func newProject() {
        stop()
        let track = Track(
            id: 0,
            number: 1,
            midiChannel: 1,
            memo: "Track 1",
            events: [TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)]
        )
        let fresh = Song(
            title: "",
            timeBase: 48,
            tempoBPM: 120,
            beatNumerator: 4,
            beatDenominator: 4,
            tracks: [track]
        )
        isRestoringHistory = true
        song = fresh
        isRestoringHistory = false
        editStart = nil
        undoSongs.removeAll()
        redoSongs.removeAll()
        selectedTrackID = track.id
        title = ""
        currentFileURL = nil
        savedSong = fresh
        refreshDirtyState()
        errorMessage = nil
        historyRevision += 1
        try? rebuildPlayback(resetPosition: true)
        state = .loaded
        refreshHistoryAvailability()
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

    public func save() throws {
        guard let currentFileURL else { throw ProjectFileError.noCurrentFile }
        try save(to: currentFileURL)
    }

    public func save(to url: URL) throws {
        let data = try encodedRCP()
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try data.write(to: url, options: .atomic)
        currentFileURL = url
        savedSong = song
        refreshDirtyState()
    }

    /// Records the URL written by SwiftUI's Save As exporter.
    public func recordSavedFile(at url: URL) {
        currentFileURL = url
        savedSong = song
        refreshDirtyState()
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

    /// Replaces raw track records while retaining the edit transaction that
    /// was opened by the track editor. This lets multi-record inline values,
    /// such as STed2 comments, be undone as one operation.
    public func replaceEventsDuringEdit(trackID: Int, in range: Range<Int>, with events: [TrackEvent]) {
        guard let index = song?.tracks.firstIndex(where: { $0.id == trackID }) else { return }
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
        edited.title = String(title.prefix(64))
        edited.tempoBPM = min(255, max(1, tempoBPM))
        edited.beatNumerator = min(32, max(1, numerator))
        edited.beatDenominator = [1, 2, 4, 8, 16, 32].contains(denominator) ? denominator : 4
        song = edited
        self.title = edited.title
        try? rebuildPlayback(resetPosition: false)
    }

    public var canAddTrack: Bool { (song?.tracks.count ?? 36) < 36 }

    @discardableResult
    public func insertSameMeasure(trackID: Int, at row: Int, referringTo measure: Int) -> Bool {
        editSameMeasures(trackID: trackID) { try $0.insertSameMeasure(at: row, referringTo: measure) }
    }

    @discardableResult
    public func expandSameMeasures(trackID: Int, in range: Range<Int>) -> Bool {
        editSameMeasures(trackID: trackID) { try $0.expandSameMeasures(in: range) }
    }

    @discardableResult
    public func compressSameMeasures(trackID: Int) -> Bool {
        editSameMeasures(trackID: trackID) { try $0.compressSameMeasures() }
    }

    private func editSameMeasures(trackID: Int, edit: (inout Track) throws -> Void) -> Bool {
        guard var edited = song, let index = edited.tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        do {
            try edit(&edited.tracks[index])
            song = edited
            try rebuildPlayback(resetPosition: false)
            return true
        } catch {
            reportError(error)
            return false
        }
    }

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

        while playbackBuildPending {
            guard let playbackBuildTask else { break }
            await playbackBuildTask.value
        }

        // Pressing play while already playing is an explicit restart. Make
        // that restart use the newest editor snapshot instead of a plan that
        // may still be waiting for the next measure boundary.
        if state == .playing, let latestPlaybackPlan {
            audio.panic()
            runtime.load(plan: latestPlaybackPlan)
            adoptActivePlan(latestPlaybackPlan, timelineOffset: 0)
        } else if state == .loaded,
                  let latestPlaybackPlan,
                  latestPlaybackPlan.revision != activePlanRevision {
            runtime.load(plan: latestPlaybackPlan)
            adoptActivePlan(latestPlaybackPlan, timelineOffset: 0)
        }

        let startSequence = activeSequence ?? sequence
        if let start = PlaybackStart.seconds(
            fromMeasure: measure,
            isPaused: state == .paused,
            song: song,
            sequence: startSequence
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
        let pausedPosition = runtime.pause()
        let pausedTick = activeSequence?.tick(
            atSeconds: max(0, pausedPosition - activeTimelineOffset)
        ) ?? 0
        audio.panic()
        stopClock()

        if let latestPlaybackPlan,
           latestPlaybackPlan.revision != activePlanRevision {
            runtime.replace(plan: latestPlaybackPlan, preservingTick: pausedTick)
            adoptActivePlan(latestPlaybackPlan, timelineOffset: 0)
            pausedAt = latestPlaybackPlan.sequence.seconds(atTick: pausedTick)
            positionSeconds = pausedAt
            songEndSeconds = latestPlaybackPlan.songEndSeconds
        } else {
            pausedAt = pausedPosition
            positionSeconds = pausedPosition
        }
        state = .paused
    }

    public func stop() {
        let needsLatestPlan = playbackBuildPending
        invalidatePlaybackBuild()
        runtime.stop()
        audio.panic()
        stopClock()
        pausedAt = 0
        positionSeconds = 0
        if let latestPlaybackPlan {
            if runtime.snapshot().planRevision != latestPlaybackPlan.revision {
                runtime.load(plan: latestPlaybackPlan)
            }
            adoptActivePlan(latestPlaybackPlan, timelineOffset: 0)
        } else {
            activeTimelineOffset = 0
        }
        if song != nil {
            state = .loaded
        } else {
            state = .empty
        }
        if needsLatestPlan {
            try? rebuildPlayback(resetPosition: false)
        }
    }

    private func rebuildPlayback(resetPosition: Bool) throws {
        guard let song else { return }
        if state == .playing && !resetPosition {
            schedulePlaybackBuild(from: song)
            return
        }

        // A synchronous rebuild (for example, an edit made while paused)
        // supersedes any asynchronous build that was started while playing.
        invalidatePlaybackBuild()
        let pausedTick: Int? = state == .paused
            ? activeSequence?.tick(atSeconds: max(0, positionSeconds - activeTimelineOffset))
            : nil

        let plan = try makePlaybackPlan(from: song)
        publishPlaybackPlan(plan, resetPosition: resetPosition, preservingTick: pausedTick)
    }

    private func makePlaybackPlan(from song: Song) throws -> PlaybackPlan {
        let decoded: RCPSequence
        do {
            decoded = try song.playbackSequence()
        } catch RCPError.noEvents {
            decoded = RCPSequence(
                timeBase: song.timeBase,
                tempoBPM: song.tempoBPM,
                beatNumerator: song.beatNumerator,
                beatDenominator: song.beatDenominator,
                lastBarSeconds: 0,
                events: []
            )
        }
        return makePlaybackPlan(from: decoded)
    }

    private func schedulePlaybackBuild(from source: Song) {
        playbackBuildRequestID += 1
        let requestID = playbackBuildRequestID
        playbackBuildPending = true
        playbackBuildTask?.cancel()

        playbackBuildTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 40_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                compilePlaybackSequence(source)
            }.value

            guard !Task.isCancelled else { return }
            self?.finishPlaybackBuild(requestID: requestID, result: result)
        }
    }

    private func finishPlaybackBuild(
        requestID: Int,
        result: Result<RCPSequence, RCPError>
    ) {
        guard requestID == playbackBuildRequestID else { return }
        playbackBuildTask = nil
        playbackBuildPending = false

        let sequence: RCPSequence
        switch result {
        case .success(let compiled):
            sequence = compiled
        case .failure(.noEvents):
            guard let song else { return }
            sequence = RCPSequence(
                timeBase: song.timeBase,
                tempoBPM: song.tempoBPM,
                beatNumerator: song.beatNumerator,
                beatDenominator: song.beatDenominator,
                lastBarSeconds: 0,
                events: []
            )
        case .failure(let error):
            reportError(error)
            return
        }

        let pausedTick: Int? = state == .paused
            ? activeSequence?.tick(atSeconds: max(0, positionSeconds - activeTimelineOffset))
            : nil
        let plan = makePlaybackPlan(from: sequence)
        publishPlaybackPlan(plan, resetPosition: false, preservingTick: pausedTick)
    }

    private func makePlaybackPlan(from sequence: RCPSequence) -> PlaybackPlan {
        playbackRevision += 1
        return PlaybackPlan(
            revision: playbackRevision,
            sequence: sequence,
            songEndSeconds: sequence.songEndSeconds + sequence.lastBarSeconds
        )
    }

    private func publishPlaybackPlan(
        _ plan: PlaybackPlan,
        resetPosition: Bool,
        preservingTick pausedTick: Int?
    ) {
        registerPlaybackPlan(plan)

        if resetPosition {
            runtime.load(plan: plan)
            adoptActivePlan(plan, timelineOffset: 0)
            positionSeconds = 0
            pausedAt = 0
            return
        }

        switch state {
        case .playing:
            // Do not replace the scheduler that is being rendered. The
            // runtime queues this immutable plan for the next bar boundary.
            runtime.queue(plan: plan)

        case .paused:
            let tick = pausedTick ?? 0
            runtime.replace(plan: plan, preservingTick: tick)
            adoptActivePlan(plan, timelineOffset: 0)
            positionSeconds = plan.sequence.seconds(atTick: tick)
            pausedAt = positionSeconds
            songEndSeconds = plan.songEndSeconds

        case .empty, .loaded:
            runtime.load(plan: plan)
            adoptActivePlan(plan, timelineOffset: 0)
            positionSeconds = 0
            pausedAt = 0
        }
    }

    private func registerPlaybackPlan(_ plan: PlaybackPlan) {
        sequence = plan.sequence
        latestPlaybackPlan = plan
        playbackPlans[plan.revision] = plan

        // Keep the active plan and a small amount of recent history so the UI
        // can adopt a plan that was switched by the render thread before the
        // next main-actor clock tick arrives.
        if playbackPlans.count > 8 {
            let protected = Set([activePlanRevision, plan.revision])
            for revision in playbackPlans.keys.sorted()
                where playbackPlans.count > 4 && !protected.contains(revision) {
                playbackPlans.removeValue(forKey: revision)
            }
        }
    }

    private func adoptActivePlan(_ plan: PlaybackPlan, timelineOffset: Double) {
        activeSequence = plan.sequence
        activePlanRevision = plan.revision
        activeTimelineOffset = timelineOffset
        songEndSeconds = max(0, plan.songEndSeconds + timelineOffset)
    }

    private func adoptActivePlanIfAvailable(
        revision: Int,
        timelineOffset: Double
    ) {
        guard let plan = playbackPlans[revision] else { return }
        adoptActivePlan(plan, timelineOffset: timelineOffset)
    }

    private func updateActivePlanFromRuntime(
        revision: Int,
        timelineOffset: Double
    ) {
        adoptActivePlanIfAvailable(revision: revision, timelineOffset: timelineOffset)
    }

    private func updateActivePlanFromRuntimeSnapshot(
        _ snapshot: (
            position: Double,
            playing: Bool,
            finished: Bool,
            planRevision: Int,
            timelineOffset: Double
        )
    ) {
        updateActivePlanFromRuntime(
            revision: snapshot.planRevision,
            timelineOffset: snapshot.timelineOffset
        )
    }

    private func invalidatePlaybackBuild() {
        playbackBuildRequestID += 1
        playbackBuildTask?.cancel()
        playbackBuildTask = nil
        playbackBuildPending = false
    }

    private func tick() {
        let snapshot = runtime.snapshot()
        updateActivePlanFromRuntimeSnapshot(snapshot)
        positionSeconds = snapshot.position
        if snapshot.finished {
            stop()
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

}

private func compilePlaybackSequence(_ song: Song) -> Result<RCPSequence, RCPError> {
    do {
        return .success(try song.playbackSequence())
    } catch let error as RCPError {
        return .failure(error)
    } catch {
        // Song.playbackSequence currently reports only RCPError. Keep the
        // worker's result typed and Sendable if that implementation grows a
        // new throwing path later.
        return .failure(.nonFiniteTime)
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
