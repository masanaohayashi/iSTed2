import AudioToolbox
import STedCore

public final class EventScheduler: @unchecked Sendable {
    private let events: [TimedMIDIEvent]
    private var nextIndex = 0
    private var prefixEvents: [[UInt8]] = []
    private var nextPrefixIndex = 0
    private var prefixStartSeconds = 0.0
    private var prefixIntervalSeconds = 0.0
    private var prefixEndSeconds = 0.0
    /// Offset applied when a compiled sequence is installed in the middle of
    /// an already-running wall-clock timeline. Event times remain relative to
    /// the sequence; the scheduler compares their translated times instead.
    private var timelineOffset = 0.0
    /// Additional delay applied to musical events while a seek prefix is being
    /// sent. The prefix itself is scheduled at its own wall-clock times.
    private var eventDelaySeconds = 0.0

    public init(events: [TimedMIDIEvent]) {
        self.events = events
    }

    public var isFinished: Bool {
        nextIndex >= events.count && nextPrefixIndex >= prefixEvents.count
    }

    public func advance(to seconds: Double, send: ([UInt8]) -> Void) {
        emitPrefix(until: seconds) { bytes, _ in send(bytes) }
        guard seconds >= prefixEndSeconds else { return }
        while nextIndex < events.count && translatedSeconds(for: events[nextIndex]) <= seconds {
            send(events[nextIndex].bytes)
            nextIndex += 1
        }
    }

    public func advance(
        to seconds: Double,
        bufferStart: Double,
        sampleRate: Double,
        send: ([UInt8], AUEventSampleTime) -> Void
    ) {
        emitPrefix(until: seconds) { bytes, eventSeconds in
            let offset = max(
                0,
                Int(((eventSeconds - bufferStart) * sampleRate).rounded(.down))
            )
            send(bytes, AUEventSampleTime(offset))
        }
        guard seconds >= prefixEndSeconds else { return }
        while nextIndex < events.count {
            let eventSeconds = translatedSeconds(for: events[nextIndex])
            guard eventSeconds <= seconds else { break }
            let offset = max(
                0,
                Int(((eventSeconds - bufferStart) * sampleRate).rounded(.down))
            )
            send(events[nextIndex].bytes, AUEventSampleTime(offset))
            nextIndex += 1
        }
    }

    public func jump(to seconds: Double) {
        jump(to: seconds, prefix: [])
    }

    public func jump(to seconds: Double, prefix: [[UInt8]]) {
        jump(to: seconds, prefix: prefix, timelineOffset: 0)
    }

    public func jump(
        to seconds: Double,
        prefix: [[UInt8]],
        timelineOffset: Double,
        prefixIntervalSeconds: Double = 0,
        prefixTailSeconds: Double = 0
    ) {
        // Inclusive of the start time so the first step of a measure still plays.
        self.timelineOffset = timelineOffset
        let sourceSeconds = seconds - timelineOffset
        nextIndex = lowerBound { $0.seconds >= sourceSeconds }
        prefixEvents = prefix
        nextPrefixIndex = 0
        prefixStartSeconds = seconds
        self.prefixIntervalSeconds = max(0, prefixIntervalSeconds)
        let tail = max(0, prefixTailSeconds)
        eventDelaySeconds = prefix.isEmpty
            ? 0
            : self.prefixIntervalSeconds * Double(prefix.count) + tail
        prefixEndSeconds = seconds + eventDelaySeconds
    }

    public func reset() {
        nextIndex = 0
        prefixEvents.removeAll(keepingCapacity: true)
        nextPrefixIndex = 0
        prefixStartSeconds = 0
        prefixIntervalSeconds = 0
        prefixEndSeconds = 0
        timelineOffset = 0
        eventDelaySeconds = 0
    }

    private func emitPrefix(
        until seconds: Double,
        send: ([UInt8], Double) -> Void
    ) {
        while nextPrefixIndex < prefixEvents.count {
            let eventSeconds = prefixStartSeconds
                + Double(nextPrefixIndex) * prefixIntervalSeconds
            guard eventSeconds <= seconds else { break }
            send(prefixEvents[nextPrefixIndex], eventSeconds)
            nextPrefixIndex += 1
        }
    }

    private func lowerBound(_ predicate: (TimedMIDIEvent) -> Bool) -> Int {
        var lower = 0
        var upper = events.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if predicate(events[middle]) {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return lower
    }

    private func translatedSeconds(for event: TimedMIDIEvent) -> Double {
        event.seconds + timelineOffset + eventDelaySeconds
    }
}
