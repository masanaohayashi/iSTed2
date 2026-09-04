@MainActor
public protocol MIDISink: AnyObject {
    func send(_ bytes: [UInt8])
    func panic()
}

/// Hardware CoreMIDI output. Intentionally empty until MIDI ports are added.
@MainActor
public final class HardwareMIDISink: MIDISink {
    public init() {}

    public func send(_ bytes: [UInt8]) {}

    public func panic() {}
}

@MainActor
public final class FanoutMIDISink: MIDISink {
    private let sinks: [MIDISink]

    public init(_ sinks: [MIDISink]) {
        self.sinks = sinks
    }

    public func send(_ bytes: [UInt8]) {
        for sink in sinks {
            sink.send(bytes)
        }
    }

    public func panic() {
        for sink in sinks {
            sink.panic()
        }
    }
}
