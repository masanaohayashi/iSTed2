import AudioToolbox
import STedCore

public final class EventScheduler: @unchecked Sendable {
    private let events: [TimedMIDIEvent]
    private var nextIndex = 0

    public init(events: [TimedMIDIEvent]) {
        self.events = events
    }

    public var isFinished: Bool {
        nextIndex >= events.count
    }

    public func advance(to seconds: Double, send: ([UInt8]) -> Void) {
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
        nextIndex = events.firstIndex { $0.seconds > seconds } ?? events.count
    }

    public func reset() {
        nextIndex = 0
    }
}
