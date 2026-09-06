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

    public var rcpByte: UInt8 {
        switch self {
        case .play: 0
        case .mute: 1
        case .mix: 2
        case .rec: 3
        }
    }
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

    public static let defaultNote = TrackEvent(command: 60, delay: 48, param1: 36, param2: 100)
    public static let defaultInsertedNote = TrackEvent(command: 60, delay: 48, param1: 46, param2: 100)
    public static let measureLine = TrackEvent(command: 0xfd, delay: 0, param1: 0, param2: 0)
    public static let specialControllerPlaceholder = TrackEvent(command: 0, delay: 0, param1: 0, param2: 0)

    public var isTerminator: Bool {
        command == 0xfe || command == 0xff
    }
}

public struct EventRow: Equatable, Sendable {
    public var time: MusicalTime
    public var label: String
    public var isTerminator: Bool
    public var st: Int
    public var gt: Int
    public var vel: Int
    public var showsMeasure: Bool
    public var stepNumber: Int?
    public var noteText: String
    public var stText: String
    public var gtText: String
    public var velText: String
    public var isMeasureLine: Bool = false
    public var ink: TrackerInk = .white
    /// Range of raw track events represented by this visible row. Most rows
    /// contain one event; a comment row contains its `0xf6` record and all
    /// contiguous `0xf7` continuation records.
    public var sourceRange: Range<Int> = 0..<1
    public var isComment: Bool = false
    public var commentText: String = ""
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
        let end = terminatorIndex
        let played: ArraySlice<TrackEvent>
        if events[..<end].contains(where: { $0.command == 0xfc }) {
            played = (try? expandedEvents(in: 0..<end))?[...] ?? events[...]
        } else {
            // Most tracks have no SAME MEAS records. Avoid materializing a
            // second event array just to count their timed steps.
            played = events[..<end]
        }
        return played.reduce(0) { total, event in
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
        var lastMeasure = 0
        var stepInMeasure = 1
        var previousCommand: UInt8 = 0xfd
        var previousDelay: UInt8 = 1
        var appendedTerminator = false
        var eventIndex = 0
        var nextPositiveDelay = Array<Int?>(repeating: nil, count: events.count)
        var positiveDelay: Int?
        for index in stride(from: events.count - 1, through: 0, by: -1) {
            nextPositiveDelay[index] = positiveDelay
            let event = events[index]
            if event.command < 0xf7, event.delay > 0 {
                positiveDelay = Int(event.delay)
            }
        }
        while eventIndex < events.count {
            let event = events[eventIndex]
            let time = MusicalTime(
                tick: tick,
                timeBase: timeBase,
                beatNumerator: beatNumerator,
                beatDenominator: beatDenominator
            )
            if event.isTerminator {
                let cells = event.trackerCells
                rows.append(
                    EventRow(
                        time: time,
                        label: "End of Track",
                        isTerminator: true,
                        st: 0,
                        gt: 0,
                        vel: 0,
                        showsMeasure: false,
                        stepNumber: nil,
                        noteText: cells.note,
                        stText: cells.st,
                        gtText: cells.gt,
                        velText: cells.vel,
                        isMeasureLine: false,
                        ink: .white,
                        sourceRange: eventIndex..<(eventIndex + 1)
                    )
                )
                appendedTerminator = true
                break
            }

            let showsMeasure = time.measure != lastMeasure
            if showsMeasure {
                lastMeasure = time.measure
                stepInMeasure = 1
            }

            // A comment is one visible row even though the RCP record uses a
            // 0xf6 header followed by up to nine 0xf7 continuation records.
            // Continuations carry no timing and must not affect chord or step
            // numbering of the following event.
            if event.isCommentStart,
               let commentRange = TrackComment.range(in: events, startingAt: eventIndex) {
                let text = TrackComment.text(from: events[commentRange])
                rows.append(
                    EventRow(
                        time: time,
                        label: "Comment",
                        isTerminator: false,
                        st: 0,
                        gt: 0,
                        vel: 0,
                        showsMeasure: showsMeasure,
                        stepNumber: nil,
                        noteText: TrackComment.displayText(text),
                        stText: "",
                        gtText: "",
                        velText: "",
                        isMeasureLine: false,
                        ink: .white,
                        sourceRange: commentRange,
                        isComment: true,
                        commentText: text
                    )
                )
                eventIndex = commentRange.upperBound
                continue
            }

            let isNoteLike = event.command < 0xf0
            let isChord = isNoteLike
                && !showsMeasure
                && previousDelay == 0
                && previousCommand < 0xf0
            let stepNumber: Int? = isNoteLike && !isChord ? stepInMeasure : nil
            if isNoteLike && !isChord {
                stepInMeasure += 1
            }
            let cells = event.trackerCells(comparisonStep: nextPositiveDelay[eventIndex])
            let isMeasureLine = event.command == 0xfd
            rows.append(
                EventRow(
                    time: time,
                    label: event.displayLabel,
                    isTerminator: false,
                    st: Int(event.delay),
                    gt: Int(event.param1),
                    vel: Int(event.param2),
                    showsMeasure: showsMeasure,
                    stepNumber: stepNumber,
                    noteText: isMeasureLine
                        ? TrackerMeasureLine.text(
                            stepCount: stepCount(endingAtMeasureLine: eventIndex)
                        )
                        : cells.note,
                    stText: isMeasureLine ? "" : cells.st,
                    gtText: isMeasureLine ? "" : cells.gt,
                    velText: isMeasureLine ? "" : cells.vel,
                    isMeasureLine: isMeasureLine,
                    ink: event.trackerInk,
                    sourceRange: eventIndex..<(eventIndex + 1)
                )
            )
            previousCommand = event.command
            previousDelay = event.delay
            if event.command == 0xfc, let expanded = try? expandedEvents(in: eventIndex..<(eventIndex + 1)) {
                tick += expanded.filter { $0.command < 0xf5 }.reduce(0) { $0 + Int($1.delay) }
            } else if event.command < 0xf5 {
                tick += Int(event.delay)
            }
            eventIndex += 1
        }
        if !appendedTerminator {
            let time = MusicalTime(
                tick: tick,
                timeBase: timeBase,
                beatNumerator: beatNumerator,
                beatDenominator: beatDenominator
            )
            rows.append(
                EventRow(
                    time: time,
                    label: "End of Track",
                    isTerminator: true,
                    st: 0,
                    gt: 0,
                    vel: 0,
                    showsMeasure: false,
                    stepNumber: nil,
                    noteText: "End of Track",
                    stText: "",
                    gtText: "",
                    velText: "",
                    isMeasureLine: false,
                    ink: .white,
                    sourceRange: events.count..<events.count
                )
            )
        }
        return rows
    }

    public var terminatorIndex: Int {
        events.firstIndex(where: \.isTerminator) ?? events.count
    }

    /// Returns the raw event range for the comment beginning at `index`.
    /// Continuation records are included so edits and deletions treat a
    /// comment as one logical tracker row.
    public func commentRange(at index: Int) -> Range<Int>? {
        TrackComment.range(in: events, startingAt: index)
    }

    public func commentText(at index: Int) -> String? {
        guard let range = commentRange(at: index) else { return nil }
        return TrackComment.text(from: events[range])
    }

    public mutating func insertComment(_ text: String, at index: Int) {
        let clamped = min(max(0, index), terminatorIndex)
        replaceEvents(in: clamped..<clamped, with: TrackComment.events(for: text))
    }

    public mutating func replaceComment(at index: Int, with text: String) {
        guard let range = commentRange(at: index) else { return }
        replaceEvents(in: range, with: TrackComment.events(for: text))
    }

    public mutating func insertEvent(_ event: TrackEvent = .defaultNote, at index: Int) {
        let clamped = min(max(0, index), terminatorIndex)
        replaceEvents(in: clamped..<clamped, with: [event])
    }

    public mutating func insertMeasureLine(at index: Int) {
        insertEvent(.measureLine, at: index)
    }

    public mutating func replaceEvents(in range: Range<Int>, with replacement: [TrackEvent]) {
        let lower = min(max(0, range.lowerBound), terminatorIndex)
        let upper = min(max(lower, range.upperBound), terminatorIndex)
        replacePreservingReferences(in: lower..<upper, with: replacement)
    }

    public mutating func insertSpecialControllerPlaceholder(at index: Int) {
        insertEvent(.specialControllerPlaceholder, at: index)
    }

    public mutating func applySpecialController(_ code: SpecialControllerCode, at index: Int) {
        guard events.indices.contains(index), index < terminatorIndex else { return }
        events[index] = SpecialController.makeEvent(
            code,
            previousEvents: events.prefix(index),
            trackMIDIChannel: midiChannel
        )
    }

    /// Step total of the measure that ends at `index`, matching STed2 `step_cluc`.
    public func stepCount(endingAtMeasureLine index: Int) -> Int {
        guard events.indices.contains(index) else { return 0 }

        var total = 0
        var multiplier = 1
        var stack: [(multiplier: Int, total: Int, count: Int)] = []
        var cursor = index

        while cursor > 0 {
            cursor -= 1
            let event = events[cursor]
            let command = event.command
            if event.isCommentStart || event.isCommentContinuation {
                // Comments are display-only records and do not terminate the
                // backwards step-count scan for the measure line.
                continue
            }
            if command < 0xf0 {
                let delay = Int(event.delay)
                if delay != 0 {
                    total += delay * multiplier
                }
            } else if command > 0xfb {
                break
            } else if command == 0xf8 {
                var count = Int(event.delay)
                if count == 0 || count == 255 {
                    count = 1
                }
                stack.append((multiplier, total, count))
                multiplier *= count
            } else if command == 0xf9 {
                if let frame = stack.popLast() {
                    multiplier = frame.multiplier
                }
            }
        }

        for frame in stack.reversed() {
            total = frame.total + (total - frame.total) / max(1, frame.count)
        }
        return total
    }

    @discardableResult
    public mutating func insertNoteBefore(at index: Int) -> TrackEvent {
        let clamped = min(max(0, index), terminatorIndex)
        let previousNote = events[..<clamped]
            .reversed()
            .first(where: { $0.command < 0x80 })
        let event = previousNote ?? .defaultInsertedNote
        replaceEvents(in: clamped..<clamped, with: [event])
        return event
    }

    public mutating func deleteEvent(at index: Int) {
        let end = terminatorIndex
        guard end > 0, index >= 0, index < end else { return }
        if let commentRange = commentRange(at: index) {
            replaceEvents(in: commentRange, with: [])
        } else {
            replaceEvents(in: index..<(index + 1), with: [])
        }
    }

    public mutating func updateAttributes(
        midiChannel: Int?,
        startTick: Int,
        keyShift: Int,
        memo: String
    ) {
        if let midiChannel, (1...16).contains(midiChannel) {
            self.midiChannel = midiChannel
        } else {
            self.midiChannel = nil
        }
        self.startTick = min(99, max(-99, startTick))
        self.keyShift = min(63, max(-64, keyShift))
        self.memo = String(memo.prefix(36))
    }

    private mutating func ensureTerminator() {
        if events.last?.isTerminator != true {
            events.append(TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0))
        }
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

    public var ticksPerMeasure: Int {
        max(1, timeBase * beatNumerator * 4 / max(1, beatDenominator))
    }

    public func startTick(ofMeasure measure: Int) -> Int {
        max(0, measure - 1) * ticksPerMeasure
    }

    public func seconds(atTick tick: Int) -> Double {
        if let sequence = try? playbackSequence() {
            return sequence.seconds(atTick: tick)
        }
        return Double(max(0, tick)) * 60.0 / (Double(max(1, tempoBPM)) * Double(max(1, timeBase)))
    }
}

extension TrackEvent {
    var displayLabel: String {
        if isTerminator {
            return "End of Track"
        }
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
        case 0xf6: return "Comment"
        case 0xf7: return ""
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
