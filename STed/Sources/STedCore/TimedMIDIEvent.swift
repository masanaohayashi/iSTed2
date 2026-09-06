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
