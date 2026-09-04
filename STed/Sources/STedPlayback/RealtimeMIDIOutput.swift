import AudioToolbox
import Foundation

final class RenderContext: @unchecked Sendable {
    var clock: PlaybackRuntime?
    let midiOut = RealtimeMIDIOutput()
    var sampleRate: Double = 44_100
}

/// Host MIDI for the out-of-process SC-55 AUv3. Channel and SysEx both go
/// through `scheduleMIDIEventBlock` on the main queue — the render thread and
/// a private GCD queue both trip `_dispatch_assert_queue_fail` on iPhone.
final class RealtimeMIDIOutput: @unchecked Sendable {
    var scheduleBlock: AUScheduleMIDIEventBlock?
    private let lock = NSLock()

    func send(_ bytes: [UInt8], at sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        guard !bytes.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let scheduleBlock else { return }
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            scheduleBlock(sampleTime, 0, buffer.count, base)
        }
    }

    func panic() {
        for channel in 0..<16 {
            send([0xb0 | UInt8(channel), 123, 0])
            send([0xb0 | UInt8(channel), 64, 0])
        }
    }
}
