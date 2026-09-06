import AudioToolbox
import Foundation
import STedCore

final class PlaybackRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduler: EventScheduler?
    private var sequence: RCPSequence?
    private var playing = false
    private var position = 0.0
    private var songEnd = Double.infinity
    private var finished = false
    private var pendingBytes: [[UInt8]] = []
    private var pendingOffsets: [AUEventSampleTime] = []

    func load(events: [TimedMIDIEvent], songEnd: Double) {
        lock.lock()
        defer { lock.unlock() }
        install(events: events, sequence: nil, songEnd: songEnd)
    }

    func load(sequence: RCPSequence, songEnd: Double) {
        lock.lock()
        defer { lock.unlock() }
        install(events: sequence.events, sequence: sequence, songEnd: songEnd)
    }

    private func install(
        events: [TimedMIDIEvent],
        sequence: RCPSequence?,
        songEnd: Double
    ) {
        scheduler = EventScheduler(events: events)
        self.sequence = sequence
        self.songEnd = songEnd
        position = 0
        playing = false
        finished = false
    }

    func play(from seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        if scheduler == nil {
            return
        }
        position = max(0, seconds)
        let prefix = sequence.map { sequence in
            sequence.stateEvents(beforeTick: sequence.tick(atSeconds: position))
        } ?? []
        scheduler?.jump(to: position, prefix: prefix)
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
        playing = false
        position = 0
        finished = false
        scheduler?.reset()
    }

    func snapshot() -> (position: Double, playing: Bool, finished: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (position, playing, finished)
    }

    func render(
        frameCount: Int,
        sampleRate: Double,
        send: ([UInt8], AUEventSampleTime) -> Void
    ) {
        lock.lock()
        guard playing, let scheduler, sampleRate > 0, frameCount > 0 else {
            lock.unlock()
            return
        }
        pendingBytes.removeAll(keepingCapacity: true)
        pendingOffsets.removeAll(keepingCapacity: true)
        let bufferStart = position
        let quantum = max(1, Int((sampleRate * 0.001).rounded(.down)))
        var frame = 0
        while frame < frameCount {
            let seconds = bufferStart + Double(frame) / sampleRate
            scheduler.advance(
                to: seconds,
                bufferStart: bufferStart,
                sampleRate: sampleRate,
                send: { bytes, offset in
                    pendingBytes.append(bytes)
                    pendingOffsets.append(offset)
                }
            )
            frame += quantum
        }
        let end = bufferStart + Double(frameCount) / sampleRate
        scheduler.advance(
            to: end,
            bufferStart: bufferStart,
            sampleRate: sampleRate,
            send: { bytes, offset in
                pendingBytes.append(bytes)
                pendingOffsets.append(offset)
            }
        )
        position = end
        if end > songEnd {
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
}
