import AudioToolbox
import STedCore

public final class EventScheduler: @unchecked Sendable {
    private let events: [TimedMIDIEvent]
    private var nextIndex = 0
    private var prefixEvents: [[UInt8]] = []
    private var nextPrefixIndex = 0

    public init(events: [TimedMIDIEvent]) {
        self.events = events
    }

    public var isFinished: Bool {
        nextIndex >= events.count && nextPrefixIndex >= prefixEvents.count
    }

    public func advance(to seconds: Double, send: ([UInt8]) -> Void) {
        emitPrefix(send: send)
        while nextIndex < events.count && events[nextIndex].seconds <= seconds {
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
        while nextIndex < events.count && events[nextIndex].seconds <= seconds {
            let offset = max(
                0,
                Int(((events[nextIndex].seconds - bufferStart) * sampleRate).rounded(.down))
            )
            send(events[nextIndex].bytes, AUEventSampleTime(offset))
            nextIndex += 1
        }
    }

    public func jump(to seconds: Double) {
        jump(to: seconds, prefix: [])
    }

    public func jump(to seconds: Double, prefix: [[UInt8]]) {
        // Inclusive of the start time so the first step of a measure still plays.
        nextIndex = events.firstIndex { $0.seconds >= seconds } ?? events.count
        prefixEvents = prefix
        nextPrefixIndex = 0
    }

    public func reset() {
        nextIndex = 0
        prefixEvents.removeAll(keepingCapacity: true)
        nextPrefixIndex = 0
    }

    private func emitPrefix(send: ([UInt8]) -> Void) {
        while nextPrefixIndex < prefixEvents.count {
            send(prefixEvents[nextPrefixIndex])
            nextPrefixIndex += 1
        }
    }
}
