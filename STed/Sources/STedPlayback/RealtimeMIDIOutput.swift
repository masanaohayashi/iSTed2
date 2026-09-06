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
    private let lock = NSLock()
    /// Serializes the final call into the audio unit with `panic()`. This
    /// prevents a render callback that was already preparing a message from
    /// scheduling it after the stop-time reset.
    private let scheduleLock = NSLock()
    private var scheduleBlock: AUScheduleMIDIEventBlock?
    /// Number of note-ons that have not been matched by a note-off for each
    /// channel/note pair. A fixed-size array keeps the audio callback free of
    /// Set/Dictionary allocations.
    private var activeNoteCounts = [UInt16](repeating: 0, count: 16 * 128)
    private var outputGeneration = 0
    private var isSuppressed = false

    func bind(scheduleBlock: AUScheduleMIDIEventBlock?) {
        scheduleLock.lock()
        lock.lock()
        self.scheduleBlock = scheduleBlock
        activeNoteCounts = [UInt16](repeating: 0, count: 16 * 128)
        outputGeneration &+= 1
        isSuppressed = false
        lock.unlock()
        scheduleLock.unlock()
    }

    /// Re-enables MIDI delivery after a stop/panic. Keeping this separate
    /// from `panic()` lets a stale render callback be discarded until the
    /// next explicit play operation starts.
    func beginPlayback() {
        scheduleLock.lock()
        lock.lock()
        outputGeneration &+= 1
        activeNoteCounts = [UInt16](repeating: 0, count: 16 * 128)
        isSuppressed = false
        lock.unlock()
        scheduleLock.unlock()
    }

    func send(_ bytes: [UInt8], at sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        guard !bytes.isEmpty else { return }
        lock.lock()
        guard !isSuppressed, self.scheduleBlock != nil else {
            lock.unlock()
            return
        }
        let generation = outputGeneration
        updateActiveNotes(for: bytes)
        lock.unlock()

        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        lock.lock()
        guard !isSuppressed,
              generation == outputGeneration,
              let scheduleBlock = self.scheduleBlock else {
            lock.unlock()
            return
        }
        lock.unlock()
        schedule(bytes, at: sampleTime, using: scheduleBlock)
    }

    func panic() {
        lock.lock()
        let activeNotes = activeNoteCounts.enumerated().compactMap { index, count -> (UInt8, UInt8)? in
            guard count > 0 else { return nil }
            return (UInt8(index / 128), UInt8(index % 128))
        }
        activeNoteCounts = [UInt16](repeating: 0, count: 16 * 128)
        outputGeneration &+= 1
        isSuppressed = true
        lock.unlock()

        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        lock.lock()
        let scheduleBlock = self.scheduleBlock
        lock.unlock()
        guard let scheduleBlock else { return }

        for channel in 0..<16 {
            schedule([0xb0 | UInt8(channel), 123, 0], using: scheduleBlock)
            schedule([0xb0 | UInt8(channel), 64, 0], using: scheduleBlock)
        }
        // Some instruments do not reliably act on CC 123 for voices that are
        // already sounding. Follow the channel-mode messages with explicit
        // note-offs for every note that was sent a note-on.
        for (channel, note) in activeNotes {
            schedule([0x80 | channel, note, 0], using: scheduleBlock)
        }
    }

    private func schedule(
        _ bytes: [UInt8],
        at sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate,
        using scheduleBlock: AUScheduleMIDIEventBlock
    ) {
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            scheduleBlock(sampleTime, 0, buffer.count, base)
        }
    }

    private func updateActiveNotes(for bytes: [UInt8]) {
        guard bytes.count >= 3 else { return }
        let status = bytes[0]
        guard status >= 0x80, status < 0xf0 else { return }
        let kind = status & 0xf0
        guard kind == 0x80 || kind == 0x90 else { return }

        let index = Int(status & 0x0f) * 128 + Int(bytes[1] & 0x7f)
        if kind == 0x90, bytes[2] & 0x7f > 0 {
            activeNoteCounts[index] = activeNoteCounts[index] == .max
                ? .max
                : activeNoteCounts[index] + 1
        } else if activeNoteCounts[index] > 0 {
            activeNoteCounts[index] -= 1
        }
    }
}
