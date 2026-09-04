public enum TrackMode: Equatable, Sendable {
    case play
    case mute
    case mix
    case rec

    public init(rcpByte: UInt8) {
        switch rcpByte {
        case 1: self = .mute
        case 2: self = .mix
        case 3, 4: self = .rec
        default: self = .play
        }
    }

    public var isMuted: Bool { self == .mute }
}

public struct MusicalTime: Equatable, Sendable {
    public var measure: Int
    public var step: Int
    public var tick: Int

    public init(tick: Int, timeBase: Int, beatNumerator: Int, beatDenominator: Int) {
        let ticksPerMeasure = max(1, timeBase * beatNumerator * 4 / max(1, beatDenominator))
        let safeTick = max(0, tick)
        self.tick = safeTick
        self.measure = safeTick / ticksPerMeasure + 1
        self.step = safeTick % ticksPerMeasure
    }
}

public struct TrackEvent: Equatable, Sendable {
    public var command: UInt8
    public var delay: UInt8
    public var param1: UInt8
    public var param2: UInt8

    public init(command: UInt8, delay: UInt8, param1: UInt8, param2: UInt8) {
        self.command = command
        self.delay = delay
        self.param1 = param1
        self.param2 = param2
    }
}

public struct EventRow: Equatable, Sendable {
    public var time: MusicalTime
    public var label: String
    public var st: Int
    public var gt: Int
    public var vel: Int
}

public struct Track: Equatable, Identifiable, Sendable {
    public var id: Int
    public var number: Int
    public var mode: TrackMode
    public var midiChannel: Int?
    public var keyShift: Int
    public var startTick: Int
    public var rhythm: UInt8
    public var memo: String
    public var events: [TrackEvent]

    public init(
        id: Int,
        number: Int,
        mode: TrackMode = .play,
        midiChannel: Int? = 1,
        keyShift: Int = 0,
        startTick: Int = 0,
        rhythm: UInt8 = 0,
        memo: String = "",
        events: [TrackEvent] = []
    ) {
        self.id = id
        self.number = number
        self.mode = mode
        self.midiChannel = midiChannel
        self.keyShift = keyShift
        self.startTick = startTick
        self.rhythm = rhythm
        self.memo = memo
        self.events = events
    }

    public var stepCount: Int {
        events.reduce(0) { total, event in
            event.command < 0xf5 ? total + Int(event.delay) : total
        }
    }

    public func eventRows(
        timeBase: Int,
        beatNumerator: Int,
        beatDenominator: Int
    ) -> [EventRow] {
        var tick = startTick
        var rows: [EventRow] = []
        for event in events {
            if event.command == 0xfe || event.command == 0xff {
                break
            }
            rows.append(
                EventRow(
                    time: MusicalTime(
                        tick: tick,
                        timeBase: timeBase,
                        beatNumerator: beatNumerator,
                        beatDenominator: beatDenominator
                    ),
                    label: event.displayLabel,
                    st: Int(event.delay),
                    gt: Int(event.param1),
                    vel: Int(event.param2)
                )
            )
            if event.command < 0xf5 {
                tick += Int(event.delay)
            }
        }
        return rows
    }
}

public struct Song: Equatable, Sendable {
    public var title: String
    public var timeBase: Int
    public var tempoBPM: Int
    public var beatNumerator: Int
    public var beatDenominator: Int
    public var tracks: [Track]
    var userSysEx: [[UInt8]]

    public init(
        title: String,
        timeBase: Int,
        tempoBPM: Int,
        beatNumerator: Int = 4,
        beatDenominator: Int = 4,
        tracks: [Track],
        userSysEx: [[UInt8]] = []
    ) {
        self.title = title
        self.timeBase = timeBase
        self.tempoBPM = tempoBPM
        self.beatNumerator = beatNumerator
        self.beatDenominator = beatDenominator
        self.tracks = tracks
        self.userSysEx = userSysEx
    }

    public func musicalTime(atTick tick: Int) -> MusicalTime {
        MusicalTime(
            tick: tick,
            timeBase: timeBase,
            beatNumerator: beatNumerator,
            beatDenominator: beatDenominator
        )
    }
}

extension TrackEvent {
    var displayLabel: String {
        if command < 0x80 {
            return noteName(command)
        }
        switch command {
        case 0xeb: return "CC\(param1)"
        case 0xec: return "PC\(param1)"
        case 0xee: return "PITCH"
        case 0xe7: return "TEMPO"
        case 0xe6: return "CH"
        case 0xf9: return "REP["
        case 0xf8: return "]REP"
        case 0xfc: return "SAME"
        case 0xfd: return "MEAS"
        default:
            return String(format: "%02X", command)
        }
    }
}

private func noteName(_ note: UInt8) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let pitch = Int(note)
    return "\(names[pitch % 12])\(pitch / 12 - 1)"
}
