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

public struct RCPSequence: Equatable, Sendable {
    public var timeBase: Int
    public var tempoBPM: Int
    public var beatNumerator: Int
    public var beatDenominator: Int
    public var songEndSeconds: Double
    public var lastBarSeconds: Double
    public var events: [TimedMIDIEvent]

    public init(
        timeBase: Int,
        tempoBPM: Int,
        beatNumerator: Int = 4,
        beatDenominator: Int = 4,
        songEndSeconds: Double = 0,
        lastBarSeconds: Double = 2,
        events: [TimedMIDIEvent]
    ) {
        self.timeBase = timeBase
        self.tempoBPM = tempoBPM
        self.beatNumerator = beatNumerator
        self.beatDenominator = beatDenominator
        self.songEndSeconds = songEndSeconds
        self.lastBarSeconds = lastBarSeconds
        self.events = events
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
