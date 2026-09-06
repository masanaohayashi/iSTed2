import AudioToolbox
import Foundation
import STedCore

/// An immutable, compiled view of a song used exclusively by the playback
/// side. The editor may continue changing its `Song` while this value is
/// active; a newer plan is installed only at a scheduler handoff point.
struct PlaybackPlan: Equatable, Sendable {
    let revision: Int
    let sequence: RCPSequence
    let songEndSeconds: Double
}

private struct PendingHandoff {
    let plan: PlaybackPlan
    let boundaryTick: Int
    let boundaryWallSeconds: Double
    let timelineOffset: Double
    let scheduler: EventScheduler
    let prefix: [[UInt8]]
}

final class PlaybackRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduler: EventScheduler?
    private var sequence: RCPSequence?
    private var activePlan: PlaybackPlan?
    private var pendingHandoff: PendingHandoff?
    /// State restoration has its own clock. While it is active, `position`
    /// remains at the requested musical start and the regular scheduler does
    /// not advance.
    private var catchupScheduler: EventScheduler?
    private var catchupElapsedSeconds = 0.0
    private var catchupDurationSeconds = 0.0
    private var planRevision = 0
    /// Changes whenever the active playback session is replaced or stopped.
    /// A handoff is prepared off the runtime lock, so this token prevents a
    /// stale preparation from being installed after a stop/load/restart.
    private var playbackGeneration = 0
    /// Wall-clock seconds from the beginning of the current play operation.
    /// The active sequence may have a different origin after a live swap.
    private var timelineOffset = 0.0
    private var playing = false
    private var position = 0.0
    private var songEnd = Double.infinity
    private var finished = false
    private var pendingBytes: [[UInt8]] = []
    private var pendingOffsets: [AUEventSampleTime] = []

    func load(events: [TimedMIDIEvent], songEnd: Double) {
        lock.lock()
        defer { lock.unlock() }
        install(
            events: events,
            sequence: nil,
            plan: nil,
            position: 0,
            timelineOffset: 0,
            playing: false,
            songEnd: songEnd
        )
    }

    func load(sequence: RCPSequence, songEnd: Double) {
        load(plan: PlaybackPlan(revision: 0, sequence: sequence, songEndSeconds: songEnd))
    }

    func load(plan: PlaybackPlan) {
        lock.lock()
        defer { lock.unlock() }
        install(plan: plan, position: 0, timelineOffset: 0, playing: false)
    }

    /// Replaces a paused plan while preserving the musical tick. No MIDI is
    /// emitted here because the runtime is not rendering while paused.
    func replace(plan: PlaybackPlan, preservingTick tick: Int) {
        lock.lock()
        defer { lock.unlock() }
        let seconds = plan.sequence.seconds(atTick: tick)
        install(plan: plan, position: seconds, timelineOffset: 0, playing: false)
        scheduler?.jump(to: seconds, prefix: [], timelineOffset: 0)
    }

    /// Publishes a newer plan without touching the active scheduler. The
    /// latest plan wins and is applied at the next measure boundary.
    func queue(plan: PlaybackPlan) {
        lock.lock()
        guard plan.revision > planRevision else {
            lock.unlock()
            return
        }
        guard playing, let activePlan, let sequence else {
            install(plan: plan, position: 0, timelineOffset: 0, playing: false)
            lock.unlock()
            return
        }

        if let pendingHandoff, plan.revision <= pendingHandoff.plan.revision {
            lock.unlock()
            return
        }

        let generation = playbackGeneration

        let currentSequenceSeconds = max(0, position - timelineOffset)
        let currentTick = sequence.tick(atSeconds: currentSequenceSeconds)
        let ticksPerMeasure = max(
            1,
            activePlan.sequence.timeBase
                * activePlan.sequence.beatNumerator
                * 4
                / max(1, activePlan.sequence.beatDenominator)
        )
        let nextMeasure = currentTick / ticksPerMeasure + 1
        let proposedBoundary = min(Int.max - ticksPerMeasure, nextMeasure * ticksPerMeasure)

        // If a new edit arrives before an already selected boundary, keep that
        // boundary so a burst of edits still produces one atomic handoff.
        let boundaryTick: Int
        let boundaryWallSeconds: Double
        if let pendingHandoff,
           pendingHandoff.boundaryWallSeconds > position + 1e-9 {
            boundaryTick = pendingHandoff.boundaryTick
            boundaryWallSeconds = pendingHandoff.boundaryWallSeconds
        } else {
            boundaryTick = proposedBoundary
            boundaryWallSeconds = activePlan.sequence.seconds(atTick: proposedBoundary) + timelineOffset
        }

        // Compiling the handoff scans the edited event list to collect state
        // messages. Do that without holding the same lock used by the audio
        // callback; otherwise a large edit can stall a render deadline.
        lock.unlock()
        let handoff = prepareHandoff(
            plan: plan,
            boundaryTick: boundaryTick,
            boundaryWallSeconds: boundaryWallSeconds
        )

        lock.lock()
        defer { lock.unlock() }
        guard playbackGeneration == generation,
              playing,
              plan.revision > planRevision else { return }
        if let pendingHandoff, plan.revision <= pendingHandoff.plan.revision {
            return
        }
        pendingHandoff = handoff
    }

    func play(from seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard scheduler != nil else { return }
        position = max(0, seconds)
        let sequenceSeconds = max(0, position - timelineOffset)
        let prefix: [[UInt8]]
        let prefixIntervalSeconds: Double
        if let sequence {
            prefix = sequence.stateEvents(beforeTick: sequence.tick(atSeconds: sequenceSeconds))
            prefixIntervalSeconds = PlaybackCatchupTiming.interval(
                for: prefix.count,
                sequence: sequence
            )
        } else {
            prefix = []
            prefixIntervalSeconds = 0
        }

        // The musical scheduler starts at the requested position only after
        // the separate catch-up scheduler has restored the instrument state.
        scheduler?.jump(to: position, prefix: [], timelineOffset: timelineOffset)
        catchupScheduler = nil
        catchupElapsedSeconds = 0
        catchupDurationSeconds = 0
        if !prefix.isEmpty {
            let catchup = EventScheduler(events: [])
            catchup.jump(
                to: 0,
                prefix: prefix,
                timelineOffset: 0,
                prefixIntervalSeconds: prefixIntervalSeconds,
                prefixTailSeconds: PlaybackCatchupTiming.settleSeconds
            )
            catchupScheduler = catchup
            catchupDurationSeconds = prefixIntervalSeconds * Double(prefix.count)
                + PlaybackCatchupTiming.settleSeconds
        }
        playing = true
        finished = false
    }

    func pause() -> Double {
        lock.lock()
        defer { lock.unlock() }
        playing = false
        return position
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        playbackGeneration &+= 1
        playing = false
        position = 0
        timelineOffset = 0
        finished = false
        pendingHandoff = nil
        catchupScheduler = nil
        catchupElapsedSeconds = 0
        catchupDurationSeconds = 0
        scheduler?.reset()
    }

    func snapshot() -> (
        position: Double,
        playing: Bool,
        finished: Bool,
        planRevision: Int,
        timelineOffset: Double
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (position, playing, finished, planRevision, timelineOffset)
    }

    func render(
        frameCount: Int,
        sampleRate: Double,
        send: ([UInt8], AUEventSampleTime) -> Void
    ) {
        lock.lock()
        guard playing, scheduler != nil, sampleRate > 0, frameCount > 0 else {
            lock.unlock()
            return
        }

        pendingBytes.removeAll(keepingCapacity: true)
        pendingOffsets.removeAll(keepingCapacity: true)

        let bufferDuration = Double(frameCount) / sampleRate
        var musicalDuration = bufferDuration
        var catchupDuration = 0.0
        if let catchupScheduler {
            let catchupStart = catchupElapsedSeconds
            let catchupEnd = min(
                catchupDurationSeconds,
                catchupStart + bufferDuration
            )
            catchupScheduler.advance(
                to: catchupEnd,
                bufferStart: catchupStart,
                sampleRate: sampleRate,
                send: append(bytes:offset:)
            )
            catchupDuration = max(0, catchupEnd - catchupStart)
            catchupElapsedSeconds = catchupEnd
            musicalDuration = max(0, bufferDuration - catchupDuration)
            if catchupEnd + 1e-9 >= catchupDurationSeconds {
                self.catchupScheduler = nil
                self.catchupElapsedSeconds = 0
                self.catchupDurationSeconds = 0
            }
        }

        // `position` is the musical clock. A prefix-only buffer consumes real
        // audio time but leaves that clock untouched. If the prefix ends in
        // this buffer, give the regular scheduler the remaining sample range.
        let bufferStart = position - catchupDuration
        let bufferEnd = position + musicalDuration
        var cursor = position

        while musicalDuration > 0, cursor < bufferEnd {
            guard let scheduler = self.scheduler else { break }
            if let pendingHandoff {
                let boundary = pendingHandoff.boundaryWallSeconds

                if boundary <= cursor + 1e-9 {
                    appendHandoffReset(
                        at: cursor,
                        bufferStart: bufferStart,
                        sampleRate: sampleRate
                    )
                    activate(
                        pendingHandoff,
                        at: cursor,
                        bufferStart: bufferStart,
                        sampleRate: sampleRate
                    )
                    cursor = max(cursor, boundary)
                    continue
                }

                if boundary <= bufferEnd {
                    advance(
                        scheduler,
                        from: cursor,
                        to: boundary,
                        bufferStart: bufferStart,
                        sampleRate: sampleRate
                    )
                    appendHandoffReset(
                        at: boundary,
                        bufferStart: bufferStart,
                        sampleRate: sampleRate
                    )
                    activate(
                        pendingHandoff,
                        at: boundary,
                        bufferStart: bufferStart,
                        sampleRate: sampleRate
                    )
                    cursor = boundary
                    continue
                }
            }

            advance(
                scheduler,
                from: cursor,
                to: bufferEnd,
                bufferStart: bufferStart,
                sampleRate: sampleRate
            )
            cursor = bufferEnd
        }

        position = bufferEnd
        // Do not finish while a state restore is still consuming its own
        // clock. The regular scheduler may already be empty at this point.
        if position > songEnd,
           catchupScheduler == nil,
           scheduler?.isFinished == true {
            playing = false
            finished = true
        }

        let bytes = pendingBytes
        let offsets = pendingOffsets
        lock.unlock()
        for index in bytes.indices {
            send(bytes[index], offsets[index])
        }
    }

    private func install(
        events: [TimedMIDIEvent],
        sequence: RCPSequence?,
        plan: PlaybackPlan?,
        position: Double,
        timelineOffset: Double,
        playing: Bool,
        songEnd: Double
    ) {
        playbackGeneration &+= 1
        scheduler = EventScheduler(events: events)
        self.sequence = sequence
        activePlan = plan
        pendingHandoff = nil
        catchupScheduler = nil
        catchupElapsedSeconds = 0
        catchupDurationSeconds = 0
        planRevision = plan?.revision ?? 0
        self.timelineOffset = timelineOffset
        self.songEnd = songEnd
        self.position = position
        self.playing = playing
        finished = false
    }

    private func install(
        plan: PlaybackPlan,
        position: Double,
        timelineOffset: Double,
        playing: Bool
    ) {
        install(
            events: plan.sequence.events,
            sequence: plan.sequence,
            plan: plan,
            position: position,
            timelineOffset: timelineOffset,
            playing: playing,
            songEnd: plan.songEndSeconds + timelineOffset
        )
    }

    private func advance(
        _ scheduler: EventScheduler,
        from start: Double,
        to end: Double,
        bufferStart: Double,
        sampleRate: Double
    ) {
        guard end >= start else { return }
        // EventScheduler computes each event's sample offset relative to the
        // complete audio buffer. Calling it once per segment is sufficient:
        // it emits every event whose timestamp is <= `end`, and preserves
        // the exact offset for each event. The old implementation woke the
        // scheduler every millisecond, which added dozens of scans and array
        // operations to every audio callback without improving timing.
        scheduler.advance(
            to: end,
            bufferStart: bufferStart,
            sampleRate: sampleRate,
            send: append(bytes:offset:)
        )
    }

    private func prepareHandoff(
        plan: PlaybackPlan,
        boundaryTick: Int,
        boundaryWallSeconds: Double
    ) -> PendingHandoff {
        let timelineOffset = boundaryWallSeconds - plan.sequence.seconds(atTick: boundaryTick)
        let scheduler = EventScheduler(events: plan.sequence.events)
        scheduler.jump(to: boundaryWallSeconds, prefix: [], timelineOffset: timelineOffset)
        return PendingHandoff(
            plan: plan,
            boundaryTick: boundaryTick,
            boundaryWallSeconds: boundaryWallSeconds,
            timelineOffset: timelineOffset,
            scheduler: scheduler,
            prefix: plan.sequence.stateEvents(beforeTick: boundaryTick)
        )
    }

    private func activate(
        _ handoff: PendingHandoff,
        at wallSeconds: Double,
        bufferStart: Double,
        sampleRate: Double
    ) {
        let plan = handoff.plan
        let offset: Double
        if abs(wallSeconds - handoff.boundaryWallSeconds) <= 1e-9 {
            offset = handoff.timelineOffset
        } else {
            // This is only a recovery path if a callback arrives after its
            // selected boundary. Reposition the already prepared scheduler
            // without rebuilding it on the audio thread.
            offset = wallSeconds - plan.sequence.seconds(atTick: handoff.boundaryTick)
            handoff.scheduler.jump(to: wallSeconds, prefix: [], timelineOffset: offset)
        }
        activePlan = plan
        sequence = plan.sequence
        planRevision = plan.revision
        timelineOffset = offset
        songEnd = plan.songEndSeconds + offset
        catchupScheduler = nil
        catchupElapsedSeconds = 0
        catchupDurationSeconds = 0
        let handoffOffset = max(
            0,
            Int(((wallSeconds - bufferStart) * sampleRate).rounded(.down))
        )
        for bytes in handoff.prefix {
            append(bytes: bytes, offset: AUEventSampleTime(handoffOffset))
        }
        pendingHandoff = nil
        scheduler = handoff.scheduler
        scheduler?.advance(
            to: wallSeconds,
            bufferStart: bufferStart,
            sampleRate: sampleRate,
            send: append(bytes:offset:)
        )
    }

    private func appendHandoffReset(
        at seconds: Double,
        bufferStart: Double,
        sampleRate: Double
    ) {
        let offset = max(
            0,
            Int(((seconds - bufferStart) * sampleRate).rounded(.down))
        )
        for channel in 0..<16 {
            append(
                bytes: [0xb0 | UInt8(channel), 123, 0],
                offset: AUEventSampleTime(offset)
            )
            append(
                bytes: [0xb0 | UInt8(channel), 64, 0],
                offset: AUEventSampleTime(offset)
            )
        }
    }

    private func append(bytes: [UInt8], offset: AUEventSampleTime) {
        pendingBytes.append(bytes)
        pendingOffsets.append(offset)
    }
}

/// Keeps a point-play state restore from becoming a same-sample MIDI burst.
/// STed2's default `lsp_wait=1` spaces the last-parameter transfer on the
/// track timeline. The modern renderer has already merged tracks into one
/// event stream, so use a quarter of one musical tick per message to retain
/// roughly the same wall-clock duration while allowing independent tracks to
/// overlap. A short tail lets the instrument finish applying the last state
/// before the first musical event is sent.
private enum PlaybackCatchupTiming {
    static let settleSeconds = 0.05

    static func interval(for count: Int, sequence: RCPSequence) -> Double {
        guard count > 0 else { return 0 }
        let tickSeconds = 60.0 / (
            Double(max(1, sequence.tempoBPM)) * Double(max(1, sequence.timeBase))
        )
        let baseInterval = min(0.01, max(0.001, tickSeconds * 0.25))
        let duration = min(2.0, max(0.05, baseInterval * Double(count)))
        return duration / Double(count)
    }
}
