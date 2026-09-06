public struct TimedMIDIEvent: Equatable, Sendable {
    public var seconds: Double
    public var ticks: Int
    public var bytes: [UInt8]

    public init(seconds: Double, ticks: Int, bytes: [UInt8]) {
        self.seconds = seconds
        self.ticks = ticks
        self.bytes = bytes
    }
}

public struct PlaybackTempoSegment: Equatable, Sendable {
    public var tick: Int
    public var seconds: Double
    public var bpm: Double

    public init(tick: Int, seconds: Double, bpm: Double) {
        self.tick = tick
        self.seconds = seconds
        self.bpm = bpm
    }
}

public struct RCPSequence: Equatable, Sendable {
    public var timeBase: Int
    public var tempoBPM: Int
    public var beatNumerator: Int
    public var beatDenominator: Int
    public var songEndSeconds: Double
    public var lastBarSeconds: Double
    public var events: [TimedMIDIEvent]
    public var tempoSegments: [PlaybackTempoSegment]

    public init(
        timeBase: Int,
        tempoBPM: Int,
        beatNumerator: Int = 4,
        beatDenominator: Int = 4,
        songEndSeconds: Double = 0,
        lastBarSeconds: Double = 2,
        events: [TimedMIDIEvent],
        tempoSegments: [PlaybackTempoSegment] = []
    ) {
        self.timeBase = timeBase
        self.tempoBPM = tempoBPM
        self.beatNumerator = beatNumerator
        self.beatDenominator = beatDenominator
        self.songEndSeconds = songEndSeconds
        self.lastBarSeconds = lastBarSeconds
        self.events = events
        self.tempoSegments = tempoSegments
    }

    private func segmentIndex(before predicate: (PlaybackTempoSegment) -> Bool) -> Int? {
        var lower = 0
        var upper = tempoSegments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if predicate(tempoSegments[middle]) { lower = middle + 1 } else { upper = middle }
        }
        return lower > 0 ? lower - 1 : nil
    }

    public func seconds(atTick tick: Int) -> Double {
        let tick = max(0, tick)
        let segment = segmentIndex { $0.tick <= tick }.map { tempoSegments[$0] }
            ?? PlaybackTempoSegment(tick: 0, seconds: 0, bpm: Double(max(1, tempoBPM)))
        return segment.seconds + Double(tick - segment.tick) * 60 / (max(1, segment.bpm) * Double(max(1, timeBase)))
    }

    public func tick(atSeconds seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let segment = segmentIndex { $0.seconds <= seconds }.map { tempoSegments[$0] }
            ?? PlaybackTempoSegment(tick: 0, seconds: 0, bpm: Double(max(1, tempoBPM)))
        let tick = Double(segment.tick) + (seconds - segment.seconds) * max(1, segment.bpm) * Double(max(1, timeBase)) / 60
        // Absorb floating-point round-off at exact tick boundaries.
        return Int(min(Double(Int.max - 1024), max(0, (tick + 1e-7).rounded(.down))))
    }

    /// Returns the MIDI channel state that must be sent before starting at a
    /// tick. Note events are deliberately excluded; only stateful channel
    /// messages are restored.
    public func stateEvents(beforeTick targetTick: Int) -> [[UInt8]] {
        guard targetTick > 0 else { return [] }

        var channels = Array(repeating: MIDISeekChannelState(), count: 16)
        var immediateEvents: [[UInt8]] = []
        for event in events where event.ticks < targetTick {
            guard event.bytes.count >= 2 else { continue }
            let status = event.bytes[0]
            if status == 0xf0 {
                immediateEvents.append(event.bytes)
                continue
            }
            guard status >= 0x80, status < 0xf0 else { continue }
            let channel = Int(status & 0x0f)

            switch status & 0xf0 {
            case 0xa0 where event.bytes.count >= 3:
                immediateEvents.append(event.bytes)
            case 0xb0 where event.bytes.count >= 3:
                let controller = Int(event.bytes[1] & 0x7f)
                if controller == 121 {
                    // STed2 treats Reset All Controllers as a boundary for
                    // the remembered controller values.
                    channels[channel].controls = [UInt8?](repeating: nil, count: 128)
                } else if Self.immediateControllers.contains(controller) {
                    // Bank select and RPN/NRPN messages are order-sensitive.
                    // Keep their history so Data Entry remains attached to
                    // the parameter that was selected in the source song.
                    immediateEvents.append(event.bytes)
                } else {
                    channels[channel].controls[controller] = event.bytes[2] & 0x7f
                }
            case 0xc0:
                immediateEvents.append(event.bytes)
            case 0xd0:
                immediateEvents.append(event.bytes)
            case 0xe0 where event.bytes.count >= 3:
                channels[channel].pitchBendLSB = event.bytes[1] & 0x7f
                channels[channel].pitchBendMSB = event.bytes[2] & 0x7f
            default:
                break
            }
        }

        var restored = immediateEvents
        for channel in channels.indices {
            let status = UInt8(channel)
            // STed2 flushes remembered regular controllers in descending
            // controller-number order after replaying order-sensitive data.
            for controller in stride(from: 127, through: 1, by: -1)
                where !Self.immediateControllers.contains(controller) && controller != 121 {
                if let value = channels[channel].controls[controller] {
                    restored.append([0xb0 | status, UInt8(controller), value])
                }
            }

            if let lsb = channels[channel].pitchBendLSB,
               let msb = channels[channel].pitchBendMSB {
                restored.append([0xe0 | status, lsb, msb])
            }
        }
        return restored
    }

    private static let immediateControllers: Set<Int> = [0, 6, 32, 38, 98, 99, 100, 101]
}

private struct MIDISeekChannelState {
    var controls = [UInt8?](repeating: nil, count: 128)
    var pitchBendLSB: UInt8?
    var pitchBendMSB: UInt8?
}

public enum RCPError: Error, Equatable, Sendable {
    case notRCPV2
    case truncatedHeader
    case noTracks
    case noEvents
    case interpreterLimit
    case tickOverflow
    case eventLimit
    case nonFiniteTime
}
