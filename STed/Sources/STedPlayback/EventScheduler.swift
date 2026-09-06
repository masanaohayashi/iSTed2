import AudioToolbox
import STedCore

public final class EventScheduler: @unchecked Sendable {
    private let events: [TimedMIDIEvent]
    private var nextIndex = 0
    private var prefixEvents: [[UInt8]] = []
    private var nextPrefixIndex = 0
    /// Offset applied when a compiled sequence is installed in the middle of
    /// an already-running wall-clock timeline. Event times remain relative to
    /// the sequence; the scheduler compares their translated times instead.
    private var timelineOffset = 0.0

    public init(events: [TimedMIDIEvent]) {
        self.events = events
    }

    public var isFinished: Bool {
        nextIndex >= events.count && nextPrefixIndex >= prefixEvents.count
    }

    public func advance(to seconds: Double, send: ([UInt8]) -> Void) {
        emitPrefix(send: send)
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
        emitPrefix { bytes in
            send(bytes, AUEventSampleTime(0))
        }
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

    public func jump(to seconds: Double, prefix: [[UInt8]], timelineOffset: Double) {
        // Inclusive of the start time so the first step of a measure still plays.
        self.timelineOffset = timelineOffset
        nextIndex = events.firstIndex { translatedSeconds(for: $0) >= seconds } ?? events.count
        prefixEvents = prefix
        nextPrefixIndex = 0
    }

    public func reset() {
        nextIndex = 0
        prefixEvents.removeAll(keepingCapacity: true)
        nextPrefixIndex = 0
        timelineOffset = 0
    }

    private func emitPrefix(send: ([UInt8]) -> Void) {
        while nextPrefixIndex < prefixEvents.count {
            send(prefixEvents[nextPrefixIndex])
            nextPrefixIndex += 1
        }
    }

    private func translatedSeconds(for event: TimedMIDIEvent) -> Double {
        event.seconds + timelineOffset
    }
}
