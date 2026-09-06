import Foundation

/// RCP v2 decoder. Behaviour matches the working player in
/// `Nuked-SC55-jcmoyer/Plugins/Source/RcpFilePlayer.cpp`.
public enum RCPDecoder {
    public static func song(from data: Data) throws -> Song {
        guard isRcpV2(data) else { throw RCPError.notRCPV2 }
        return try Song(document: parseDocument(data))
    }

    public static func decode(_ data: Data) throws -> RCPSequence {
        try song(from: data).playbackSequence()
    }

    public static func isRcpV2(_ data: Data) -> Bool {
        let prefix = Array(rcpHeaderPrefix.utf8)
        return data.count >= prefix.count && data.prefix(prefix.count).elementsEqual(prefix)
    }
}

extension Song {
    fileprivate init(document: RcpDocument) {
        self.init(
            title: document.title,
            timeBase: document.timeBase,
            tempoBPM: document.tempoBPM,
            beatNumerator: document.beatNumerator,
            beatDenominator: document.beatDenominator,
            tracks: document.tracks.enumerated().map { index, track in
                Track(
                    id: index,
                    number: track.number == 0 ? index + 1 : track.number,
                    mode: TrackMode(rcpByte: track.modeByte),
                    midiChannel: track.channel >= 0 ? track.channel + 1 : nil,
                    keyShift: track.transposition,
                    startTick: track.startTick,
                    rhythm: track.rhythm,
                    memo: track.memo,
                    events: track.events.map {
                        TrackEvent(command: $0.command, delay: $0.delay, param1: $0.param1, param2: $0.param2)
                    }
                )
            },
            userSysEx: document.userSysEx
        )
    }

    public func playbackSequence() throws -> RCPSequence {
        try expandPlayback(asDocument())
    }

    fileprivate func asDocument() -> RcpDocument {
        var document = RcpDocument()
        document.title = title
        document.timeBase = timeBase
        document.tempoBPM = tempoBPM
        document.beatNumerator = beatNumerator
        document.beatDenominator = beatDenominator
        document.userSysEx = userSysEx
        document.tracks = tracks.map { track in
            var rcp = RcpTrack()
            rcp.number = track.number
            rcp.channel = track.midiChannel.map { $0 - 1 } ?? -1
            rcp.transposition = track.keyShift
            rcp.startTick = track.startTick
            rcp.muted = track.mode.isMuted
            rcp.rhythm = track.rhythm
            rcp.memo = track.memo
            rcp.events = track.events.enumerated().map { index, event in
                RcpEvent(
                    command: event.command,
                    delay: event.delay,
                    param1: event.param1,
                    param2: event.param2,
                    offset: rcpTrackHeaderSize + index * rcpEventSize
                )
            }
            return rcp
        }
        return document
    }
}

private func expandPlayback(_ document: RcpDocument) throws -> RCPSequence {
    var timedEvents: [InternalEvent] = []
    var tempoModifiers: [TempoModifier] = []
    var order: UInt64 = 0
    var maximumTick: Int64 = 0

    for track in document.tracks where !track.muted {
        var expander = TrackExpander(
            document: document,
            track: track,
            output: &timedEvents,
            tempo: &tempoModifiers,
            order: &order,
            maximumTick: &maximumTick
        )
        try expander.run()
    }

    guard !timedEvents.isEmpty else { throw RCPError.noEvents }

    timedEvents.sort { lhs, rhs in
        lhs.tick != rhs.tick ? lhs.tick < rhs.tick : lhs.order < rhs.order
    }

    let timeline = TempoTimeline(document: document, modifiers: tempoModifiers)
    var events: [TimedMIDIEvent] = []
    events.reserveCapacity(timedEvents.count)
    var songEnd = 0.0

    for event in timedEvents {
        let seconds = timeline.secondsAt(event.tick)
        guard seconds.isFinite else { throw RCPError.nonFiniteTime }
        events.append(TimedMIDIEvent(seconds: seconds, ticks: Int(event.tick), bytes: event.bytes))
        songEnd = max(songEnd, seconds)
    }

    let finalBPM = timeline.finalBPM(at: maximumTick)
    let barTicks = Double(document.timeBase) * Double(document.beatNumerator) * 4.0
        / Double(document.beatDenominator)
    let lastBar = max(0.1, barTicks * 60.0 / (finalBPM * Double(document.timeBase)))

    return RCPSequence(
        timeBase: document.timeBase,
        tempoBPM: document.tempoBPM,
        beatNumerator: document.beatNumerator,
        beatDenominator: document.beatDenominator,
        songEndSeconds: songEnd,
        lastBarSeconds: lastBar,
        events: events,
        tempoSegments: timeline.segments.map {
            PlaybackTempoSegment(tick: Int($0.startTick), seconds: $0.startSeconds, bpm: $0.bpm)
        }
    )
}

private func fixedString(_ data: Data, offset: Int, length: Int) -> String {
    guard offset < data.count else { return "" }
    let end = min(data.count, offset + length)
    let bytes = [UInt8](data[offset..<end]).prefix { $0 != 0 }
    let decoded = String(bytes: bytes, encoding: .shiftJIS)
        ?? String(bytes: bytes, encoding: .isoLatin1)
        ?? ""
    return decoded.trimmingCharacters(in: .whitespaces)
}

private let rcpHeaderPrefix = "RCM-PC98V2.0(C)COME ON MUSIC"
private let rcpHeaderSize = 0x586
private let rcpTrackHeaderSize = 0x2c
private let rcpEventSize = 4
private let maximumTrackCount = 36
private let maximumTrackEvents = 250_000
private let maximumInterpreterSteps = 4_000_000
private let maximumOutputEvents = 2_000_000
private let defaultLoopCount = 2

private struct RcpEvent {
    var command: UInt8
    var delay: UInt8
    var param1: UInt8
    var param2: UInt8
    var offset: Int
}

private struct RcpTrack {
    var number: Int = 0
    var channel: Int = -1
    var transposition: Int = 0
    var startTick: Int = 0
    var rawStartTick: UInt8 = 0
    var muted: Bool = false
    var modeByte: UInt8 = 0
    var rhythm: UInt8 = 0
    var memo: String = ""
    var events: [RcpEvent] = []
}

private struct RcpDocument {
    var title = ""
    var timeBase = 48
    var tempoBPM = 120
    var beatNumerator = 4
    var beatDenominator = 4
    var hasExplicitTrackCount = false
    var userSysEx: [[UInt8]] = []
    var tracks: [RcpTrack] = []
}

private struct InternalEvent {
    var tick: Int64
    var order: UInt64
    var bytes: [UInt8]
}

private struct TempoModifier {
    var tick: Int64
    var order: UInt64
    var ratio: Int
    var gradation: Int
}

private struct TempoPoint {
    var tick: Int64
    var order: UInt64
    var bpm: Double
}

private struct ActiveNote {
    var active = false
    var offTick: Int64 = 0
    var channel = 0
}

private func signedSevenBit(_ value: UInt8) -> Int {
    (value & 0x40) != 0 ? Int(value) - 0x80 : Int(value)
}

private func decodeTrackLength(_ encoded: UInt16) -> UInt32 {
    UInt32(encoded & ~0x03) | (UInt32(encoded & 0x03) << 16)
}

private func readUInt16LE(_ data: Data, offset: Int) -> UInt16? {
    guard offset + 1 < data.count else { return nil }
    return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}

private func parseDocument(_ data: Data) throws -> RcpDocument {
    guard data.count >= rcpHeaderSize else { throw RCPError.truncatedHeader }

    var document = RcpDocument()
    document.title = fixedString(data, offset: 0x20, length: 64)
    let timeBase = UInt16(data[0x1c0]) | UInt16(data[0x1e7]) << 8
    document.timeBase = max(1, Int(timeBase))
    document.tempoBPM = max(1, Int(data[0x1c1]))
    document.beatNumerator = data[0x1c2] == 0 ? 4 : Int(data[0x1c2])
    document.beatDenominator = Int(data[0x1c3])
    if document.beatDenominator == 0
        || document.beatDenominator > 32
        || (document.beatDenominator & (document.beatDenominator - 1)) != 0
    {
        document.beatDenominator = 4
    }

    document.userSysEx = (0..<8).map { index in
        let offset = 0x406 + index * 0x30 + 0x18
        return Array(data[offset..<(offset + 0x18)])
    }

    let declaredTrackCount = Int(data[0x1e6])
    document.hasExplicitTrackCount = declaredTrackCount != 0
    let trackLimit = min(
        maximumTrackCount,
        document.hasExplicitTrackCount ? declaredTrackCount : 18
    )

    var offset = rcpHeaderSize
    for _ in 0..<trackLimit {
        guard offset + rcpTrackHeaderSize <= data.count else { break }
        if isTrackFooter(data, offset: offset) { break }
        guard let encodedLength = readUInt16LE(data, offset: offset) else { break }
        let declaredLength = Int(decodeTrackLength(encodedLength))
        guard declaredLength >= rcpTrackHeaderSize else { break }
        let trackLength = min(declaredLength, data.count - offset)
        guard trackLength >= rcpTrackHeaderSize else { break }

        var track = RcpTrack()
        track.number = Int(data[offset + 2])
        track.rhythm = data[offset + 3]
        let rawChannel = data[offset + 4]
        track.channel = (rawChannel == 0xff || (rawChannel & 0x80) != 0)
            ? -1
            : Int(rawChannel & 0x0f)
        let rawTransposition = data[offset + 5]
        track.transposition = (rawTransposition & 0x80) != 0
            ? 0
            : signedSevenBit(rawTransposition) + Int(Int8(bitPattern: data[0x1c5]))
        track.rawStartTick = data[offset + 6]
        track.startTick = Int(Int8(bitPattern: track.rawStartTick))
        track.modeByte = data[offset + 7]
        track.muted = track.modeByte == 1
        track.memo = fixedString(data, offset: offset + 8, length: 36)

        let eventBytes = trackLength - rcpTrackHeaderSize
        let eventCount = min(maximumTrackEvents, eventBytes / rcpEventSize)
        track.events.reserveCapacity(eventCount)
        for eventIndex in 0..<eventCount {
            let eventOffset = offset + rcpTrackHeaderSize + eventIndex * rcpEventSize
            let event = RcpEvent(
                command: data[eventOffset],
                delay: data[eventOffset + 1],
                param1: data[eventOffset + 2],
                param2: data[eventOffset + 3],
                offset: eventOffset - offset
            )
            track.events.append(event)
            if event.command == 0xfe || event.command == 0xff { break }
        }

        document.tracks.append(track)
        if trackLength < declaredLength { break }
        offset += trackLength
    }

    let signedStartTicks = document.hasExplicitTrackCount
        || document.tracks.allSatisfy { track in
            let signedValue = Int(Int8(bitPattern: track.rawStartTick))
            return signedValue >= -99 && signedValue <= 99
        }
    if !signedStartTicks {
        for index in document.tracks.indices {
            document.tracks[index].startTick = Int(document.tracks[index].rawStartTick)
        }
    }

    guard !document.tracks.isEmpty else { throw RCPError.noTracks }
    return document
}

private func isTrackFooter(_ data: Data, offset: Int) -> Bool {
    guard offset + 3 < data.count else { return false }
    return data[offset] == 0x52
        && data[offset + 1] == 0x43
        && data[offset + 2] == 0x46
        && data[offset + 3] == 0x57
}

private func addTimedEvent(
    _ destination: inout [InternalEvent],
    tick: Int64,
    order: inout UInt64,
    bytes: [UInt8]
) throws {
    guard !bytes.isEmpty else { return }
    guard destination.count < maximumOutputEvents else { throw RCPError.eventLimit }
    destination.append(InternalEvent(tick: max(0, tick), order: order, bytes: bytes))
    order += 1
}

private func addShortEvent(
    _ destination: inout [InternalEvent],
    tick: Int64,
    channel: Int,
    status: UInt8,
    data1: UInt8,
    data2: UInt8,
    order: inout UInt64
) throws {
    guard channel >= 0 && channel < 16 else { return }
    try addTimedEvent(
        &destination,
        tick: tick,
        order: &order,
        bytes: [status | UInt8(channel), data1 & 0x7f, data2 & 0x7f]
    )
}

private func addProgramChange(
    _ destination: inout [InternalEvent],
    tick: Int64,
    channel: Int,
    program: UInt8,
    order: inout UInt64
) throws {
    guard channel >= 0 && channel < 16 else { return }
    try addTimedEvent(
        &destination,
        tick: tick,
        order: &order,
        bytes: [0xc0 | UInt8(channel), program & 0x7f]
    )
}

private func expandSysExTemplate(
    body: [UInt8],
    param1: UInt8,
    param2: UInt8,
    channel: Int
) -> [UInt8] {
    var result: [UInt8] = [0xf0]
    var checksum = 0
    for token in body {
        if token == 0xf7 { break }
        var value = Int(token)
        switch token {
        case 0x80: value = Int(param1)
        case 0x81: value = Int(param2)
        case 0x82:
            guard channel >= 0 else { return [] }
            value = channel
        case 0x83:
            checksum = 0
            continue
        case 0x84:
            value = (0x100 - checksum) & 0x7f
        case 0xf0:
            continue
        default:
            if (token & 0x80) != 0 { continue }
        }
        value &= 0x7f
        result.append(UInt8(value))
        checksum = (checksum + value) & 0x7f
    }
    guard result.count > 1 else { return [] }
    result.append(0xf7)
    return result
}

private func addSysExTemplate(
    _ destination: inout [InternalEvent],
    tick: Int64,
    body: [UInt8],
    param1: UInt8,
    param2: UInt8,
    channel: Int,
    order: inout UInt64
) throws {
    guard channel >= 0 else { return }
    let bytes = expandSysExTemplate(body: body, param1: param1, param2: param2, channel: channel)
    guard bytes.count > 2 else { return }
    try addTimedEvent(&destination, tick: tick, order: &order, bytes: bytes)
}

private func makeChannelSysEx(
    command: UInt8,
    channel: Int,
    param1: UInt8,
    param2: UInt8
) -> [UInt8] {
    let deviceChannel = UInt8(0x10 + channel)
    var bytes: [UInt8] = [0xf0, 0x43, deviceChannel]
    switch command {
    case 0xc0: bytes.append(0x08)
    case 0xc1: bytes.append(0x00)
    case 0xc2: bytes.append(0x04)
    case 0xc3: bytes.append(0x11)
    case 0xc5: bytes.append(0x15)
    case 0xc7: bytes.append(0x12)
    case 0xc8: bytes.append(0x13)
    case 0xc9: bytes.append(0x10)
    case 0xca: bytes.append(contentsOf: [0x10, 0x7b])
    case 0xcb: bytes.append(contentsOf: [0x10, 0x7c])
    case 0xcc: bytes.append(0x1b)
    case 0xcd: bytes.append(0x18)
    case 0xce: bytes.append(0x19)
    case 0xcf: bytes.append(0x1a)
    default: return []
    }
    bytes.append(param1 & 0x7f)
    bytes.append(param2 & 0x7f)
    bytes.append(0xf7)
    return bytes
}

private func addRolandParameter(
    _ destination: inout [InternalEvent],
    tick: Int64,
    channel: Int,
    device: UInt8,
    model: UInt8,
    baseHigh: UInt8,
    baseMiddle: UInt8,
    addressLow: UInt8,
    parameter: UInt8,
    order: inout UInt64
) throws {
    guard channel >= 0 else { return }
    let checksum = UInt8((0x100 - ((Int(baseHigh) + Int(baseMiddle) + Int(addressLow) + Int(parameter)) & 0x7f)) & 0x7f)
    try addTimedEvent(
        &destination,
        tick: tick,
        order: &order,
        bytes: [
            0xf0, 0x41, device & 0x7f, model & 0x7f, 0x12,
            baseHigh & 0x7f, baseMiddle & 0x7f, addressLow & 0x7f,
            parameter & 0x7f, checksum, 0xf7
        ]
    )
}

private func skipContinuationEvents(_ events: [RcpEvent], index: Int) -> Int {
    var next = index
    while next < events.count && events[next].command == 0xf7 {
        next += 1
    }
    return next
}

private func repeatTargetIndex(_ events: [RcpEvent], event: RcpEvent) -> Int? {
    let targetOffset = Int(event.param1 & 0xfc) | (Int(event.param2) << 8)
    guard targetOffset >= rcpTrackHeaderSize,
          (targetOffset - rcpTrackHeaderSize) % rcpEventSize == 0
    else { return nil }
    let target = (targetOffset - rcpTrackHeaderSize) / rcpEventSize
    return target < events.count ? target : nil
}

private let tempoGraduationSteps: [UInt16] = [
    0, 255, 225, 208, 195, 186, 178, 171, 165, 160, 156, 151, 148, 144, 141, 138,
    135, 132, 130, 128, 125, 123, 121, 119, 117, 116, 114, 112, 111, 109, 108, 106,
    105, 104, 102, 101, 100, 99, 98, 96, 95, 94, 93, 92, 91, 90, 89, 88,
    87, 86, 86, 85, 84, 83, 82, 81, 81, 80, 79, 78, 78, 77, 76, 76,
    75, 74, 74, 73, 72, 72, 71, 70, 70, 69, 69, 68, 67, 67, 66, 66,
    65, 65, 64, 64, 63, 63, 62, 62, 61, 61, 60, 60, 59, 59, 58, 58,
    57, 57, 56, 56, 56, 55, 55, 54, 54, 53, 53, 53, 52, 52, 51, 51,
    51, 50, 50, 49, 49, 49, 48, 48, 48, 47, 47, 47, 46, 46, 45, 45,
    45, 44, 44, 44, 43, 43, 43, 42, 42, 42, 42, 41, 41, 41, 40, 40,
    40, 39, 39, 39, 38, 38, 38, 38, 37, 37, 37, 36, 36, 36, 36, 35,
    35, 35, 35, 34, 34, 34, 33, 33, 33, 33, 32, 32, 32, 32, 31, 31,
    31, 31, 30, 30, 30, 30, 29, 29, 29, 29, 29, 28, 28, 28, 28, 27,
    27, 27, 27, 26, 26, 26, 26, 26, 25, 25, 25, 25, 25, 24, 24, 24,
    24, 23, 23, 23, 23, 23, 22, 22, 22, 22, 22, 21, 21, 21, 21, 21,
    20, 20, 20, 20, 20, 20, 19, 19, 19, 19, 19, 18, 18, 18, 18, 18,
    17, 17, 17, 17, 17, 17, 16, 16, 16, 16, 16, 16, 15, 15, 15, 15
]

private func tempoGraduationTicks(gradation: Int, timeBase: Int) -> Int {
    guard gradation > 0 else { return 0 }
    let steps = tempoGraduationSteps[gradation & 0xff]
    return max(1, Int((Double(steps) * Double(timeBase) / 48.0).rounded()))
}

private struct LoopFrame {
    var startIndex: Int
    var completedPasses: Int
}

private struct TrackExpander {
    let document: RcpDocument
    let track: RcpTrack
    var output: UnsafeMutablePointer<[InternalEvent]>
    var tempo: UnsafeMutablePointer<[TempoModifier]>
    var order: UnsafeMutablePointer<UInt64>
    var maximumTick: UnsafeMutablePointer<Int64>

    var channel: Int
    var yamahaDevice: UInt8 = 0x10
    var yamahaModel: UInt8 = 0x4c
    var yamahaBaseHigh: UInt8 = 0
    var yamahaBaseMiddle: UInt8 = 0
    var rolandDevice: UInt8 = 0x10
    var rolandModel: UInt8 = 0x16
    var rolandBaseHigh: UInt8 = 0x00
    var rolandBaseMiddle: UInt8 = 0x10
    var repeatReturnIndex: Int? = nil
    var activeNotes = Array(repeating: ActiveNote(), count: 128)

    init(
        document: RcpDocument,
        track: RcpTrack,
        output: inout [InternalEvent],
        tempo: inout [TempoModifier],
        order: inout UInt64,
        maximumTick: inout Int64
    ) {
        self.document = document
        self.track = track
        self.output = withUnsafeMutablePointer(to: &output) { $0 }
        self.tempo = withUnsafeMutablePointer(to: &tempo) { $0 }
        self.order = withUnsafeMutablePointer(to: &order) { $0 }
        self.maximumTick = withUnsafeMutablePointer(to: &maximumTick) { $0 }
        self.channel = track.channel
    }

    mutating func run() throws {
        guard !track.events.isEmpty else { return }
        var index = 0
        var loops: [LoopFrame] = []
        var currentTick = Int64(track.startTick)
        var steps = 0

        while index < track.events.count {
            steps += 1
            if steps > maximumInterpreterSteps { throw RCPError.interpreterLimit }
            try flushDueNotes(currentTick)

            let event = track.events[index]
            let command = event.command

            if command < 0x80 {
                try emitNote(tick: currentTick, event: event)
                try advance(&currentTick, event.delay)
                index += 1
                continue
            }

            switch command {
            case 0x90...0x97:
                try addSysExTemplate(
                    &output.pointee,
                    tick: currentTick,
                    body: document.userSysEx[Int(command - 0x90)],
                    param1: event.param1,
                    param2: event.param2,
                    channel: channel,
                    order: &order.pointee
                )
                try advance(&currentTick, event.delay)
                index += 1

            case 0x98:
                var body: [UInt8] = [event.param1, event.param2]
                var next = index + 1
                while next < track.events.count && track.events[next].command == 0xf7 {
                    body.append(track.events[next].param1)
                    body.append(track.events[next].param2)
                    next += 1
                }
                try addSysExTemplate(
                    &output.pointee,
                    tick: currentTick,
                    body: body,
                    param1: event.param1,
                    param2: event.param2,
                    channel: channel,
                    order: &order.pointee
                )
                try advance(&currentTick, event.delay)
                index = next

            case 0x99:
                try advance(&currentTick, event.delay)
                index = skipContinuationEvents(track.events, index: index + 1)

            case 0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf:
                if channel >= 0 && command == 0xc6 {
                    try addTimedEvent(
                        &output.pointee,
                        tick: currentTick,
                        order: &order.pointee,
                        bytes: [
                            0xf0, 0x43, 0x75, UInt8(channel & 0x7f), 0x10,
                            event.param1 & 0x7f, event.param2 & 0x7f, 0xf7
                        ]
                    )
                } else {
                    try addTimedEvent(
                        &output.pointee,
                        tick: currentTick,
                        order: &order.pointee,
                        bytes: makeChannelSysEx(
                            command: command,
                            channel: channel,
                            param1: event.param1,
                            param2: event.param2
                        )
                    )
                }
                try advance(&currentTick, event.delay)
                index += 1

            case 0xd0:
                yamahaBaseHigh = event.param1
                yamahaBaseMiddle = event.param2
                try advance(&currentTick, event.delay)
                index += 1

            case 0xd1:
                yamahaDevice = event.param1
                yamahaModel = event.param2
                try advance(&currentTick, event.delay)
                index += 1

            case 0xd2:
                if channel >= 0 {
                    try addTimedEvent(
                        &output.pointee,
                        tick: currentTick,
                        order: &order.pointee,
                        bytes: [
                            0xf0, 0x43, yamahaDevice & 0x7f, yamahaModel & 0x7f,
                            yamahaBaseHigh & 0x7f, yamahaBaseMiddle & 0x7f,
                            event.param1 & 0x7f, event.param2 & 0x7f, 0xf7
                        ]
                    )
                }
                try advance(&currentTick, event.delay)
                index += 1

            case 0xd3:
                if channel >= 0 {
                    try addTimedEvent(
                        &output.pointee,
                        tick: currentTick,
                        order: &order.pointee,
                        bytes: [
                            0xf0, 0x43, 0x10, 0x4c,
                            yamahaBaseHigh & 0x7f, yamahaBaseMiddle & 0x7f,
                            event.param1 & 0x7f, event.param2 & 0x7f, 0xf7
                        ]
                    )
                }
                try advance(&currentTick, event.delay)
                index += 1

            case 0xdc:
                if channel >= 0 {
                    try addTimedEvent(
                        &output.pointee,
                        tick: currentTick,
                        order: &order.pointee,
                        bytes: [
                            0xf0, 0x41, 0x32, UInt8(channel & 0x7f),
                            event.param1 & 0x7f, event.param2 & 0x7f, 0xf7
                        ]
                    )
                }
                try advance(&currentTick, event.delay)
                index += 1

            case 0xdd:
                rolandBaseHigh = event.param1
                rolandBaseMiddle = event.param2
                try advance(&currentTick, event.delay)
                index += 1

            case 0xde:
                try addRolandParameter(
                    &output.pointee,
                    tick: currentTick,
                    channel: channel,
                    device: rolandDevice,
                    model: rolandModel,
                    baseHigh: rolandBaseHigh,
                    baseMiddle: rolandBaseMiddle,
                    addressLow: event.param1,
                    parameter: event.param2,
                    order: &order.pointee
                )
                try advance(&currentTick, event.delay)
                index += 1

            case 0xdf:
                rolandDevice = event.param1
                rolandModel = event.param2
                try advance(&currentTick, event.delay)
                index += 1

            case 0xe1:
                try addShortEvent(&output.pointee, tick: currentTick, channel: channel, status: 0xb0, data1: 32, data2: event.param2, order: &order.pointee)
                try addProgramChange(&output.pointee, tick: currentTick, channel: channel, program: event.param1, order: &order.pointee)
                try advance(&currentTick, event.delay)
                index += 1

            case 0xe2:
                try addShortEvent(&output.pointee, tick: currentTick, channel: channel, status: 0xb0, data1: 0, data2: event.param2, order: &order.pointee)
                try addShortEvent(&output.pointee, tick: currentTick, channel: channel, status: 0xb0, data1: 32, data2: 0, order: &order.pointee)
                try addProgramChange(&output.pointee, tick: currentTick, channel: channel, program: event.param1, order: &order.pointee)
                try advance(&currentTick, event.delay)
                index += 1

            case 0xe5:
                try advance(&currentTick, event.delay)
                index += 1

            case 0xe6:
                let decoded = Int(event.param1) - 1
                channel = (event.param1 == 0 || (decoded & 0x80) != 0) ? -1 : decoded & 0x0f
                try advance(&currentTick, event.delay)
                index += 1

            case 0xe7:
                tempo.pointee.append(
                    TempoModifier(
                        tick: max(0, currentTick),
                        order: order.pointee,
                        ratio: max(1, Int(event.param1)),
                        gradation: Int(event.param2)
                    )
                )
                order.pointee += 1
                try advance(&currentTick, event.delay)
                index += 1

            case 0xea:
                try addShortEvent(&output.pointee, tick: currentTick, channel: channel, status: 0xd0, data1: event.param1, data2: 0, order: &order.pointee)
                try advance(&currentTick, event.delay)
                index += 1

            case 0xeb:
                try addShortEvent(&output.pointee, tick: currentTick, channel: channel, status: 0xb0, data1: event.param1, data2: event.param2, order: &order.pointee)
                try advance(&currentTick, event.delay)
                index += 1

            case 0xec:
                if event.param1 < 0x80 {
                    try addProgramChange(&output.pointee, tick: currentTick, channel: channel, program: event.param1, order: &order.pointee)
                }
                try advance(&currentTick, event.delay)
                index += 1

            case 0xed:
                try addShortEvent(&output.pointee, tick: currentTick, channel: channel, status: 0xa0, data1: event.param1, data2: event.param2, order: &order.pointee)
                try advance(&currentTick, event.delay)
                index += 1

            case 0xee:
                try addShortEvent(&output.pointee, tick: currentTick, channel: channel, status: 0xe0, data1: event.param1, data2: event.param2, order: &order.pointee)
                try advance(&currentTick, event.delay)
                index += 1

            case 0xf5:
                index += 1

            case 0xf6:
                index = skipContinuationEvents(track.events, index: index + 1)

            case 0xf7:
                index += 1

            case 0xf8:
                try handleLoopEnd(&loops, index: &index, event: event)

            case 0xf9:
                if loops.count < 8 {
                    loops.append(LoopFrame(startIndex: index + 1, completedPasses: 0))
                }
                index += 1

            case 0xfc:
                try handleRepeatMeasure(index: &index, event: event)

            case 0xfd:
                if let ret = repeatReturnIndex {
                    index = ret
                    repeatReturnIndex = nil
                } else {
                    index += 1
                }

            case 0xfe:
                index = track.events.count

            default:
                if command < 0xf5 {
                    try advance(&currentTick, event.delay)
                }
                index += 1
            }

            maximumTick.pointee = max(maximumTick.pointee, currentTick)
        }

        try flushAllNotes()
        maximumTick.pointee = max(maximumTick.pointee, currentTick)
    }

    private func advance(_ tick: inout Int64, _ amount: UInt8) throws {
        let delta = Int64(amount)
        if delta > 0 && tick > Int64.max - delta {
            throw RCPError.tickOverflow
        }
        tick += delta
    }

    private mutating func flushDueNotes(_ tick: Int64) throws {
        for note in 0..<activeNotes.count where activeNotes[note].active && activeNotes[note].offTick <= tick {
            try addShortEvent(
                &output.pointee,
                tick: activeNotes[note].offTick,
                channel: activeNotes[note].channel,
                status: 0x80,
                data1: UInt8(note),
                data2: 0,
                order: &order.pointee
            )
            activeNotes[note].active = false
        }
    }

    private mutating func flushAllNotes() throws {
        for note in 0..<activeNotes.count where activeNotes[note].active {
            try addShortEvent(
                &output.pointee,
                tick: activeNotes[note].offTick,
                channel: activeNotes[note].channel,
                status: 0x80,
                data1: UInt8(note),
                data2: 0,
                order: &order.pointee
            )
            activeNotes[note].active = false
        }
    }

    private mutating func emitNote(tick: Int64, event: RcpEvent) throws {
        let noteValue = Int(event.command) + track.transposition
        // STed2 treats a zero gate or velocity as a silent note event.
        guard noteValue >= 0 && noteValue <= 127 && event.param1 != 0 && event.param2 != 0 else {
            return
        }

        if activeNotes[noteValue].active {
            if tick > Int64.max - Int64(event.param1) { throw RCPError.tickOverflow }
            activeNotes[noteValue].offTick = tick + Int64(event.param1)
            return
        }

        guard channel >= 0 else { return }
        try addShortEvent(
            &output.pointee,
            tick: tick,
            channel: channel,
            status: 0x90,
            data1: UInt8(noteValue),
            data2: event.param2,
            order: &order.pointee
        )
        if tick > Int64.max - Int64(event.param1) { throw RCPError.tickOverflow }
        activeNotes[noteValue].active = true
        activeNotes[noteValue].offTick = tick + Int64(event.param1)
        activeNotes[noteValue].channel = channel
    }

    private mutating func handleLoopEnd(_ loops: inout [LoopFrame], index: inout Int, event: RcpEvent) throws {
        guard !loops.isEmpty else {
            index += 1
            return
        }
        loops[loops.count - 1].completedPasses += 1
        let requested = Int(event.delay)
        let targetPasses = (requested == 0 || requested >= 0x7f) ? defaultLoopCount : requested
        if loops[loops.count - 1].completedPasses < targetPasses {
            index = loops[loops.count - 1].startIndex
        } else {
            loops.removeLast()
            index += 1
        }
    }

    private mutating func handleRepeatMeasure(index: inout Int, event: RcpEvent) throws {
        if let ret = repeatReturnIndex {
            index = ret
            repeatReturnIndex = nil
            return
        }
        guard var target = repeatTargetIndex(track.events, event: event) else {
            index += 1
            return
        }
        for _ in 0..<64 where target < track.events.count && track.events[target].command == 0xfc {
            guard let chained = repeatTargetIndex(track.events, event: track.events[target]),
                  chained != target
            else {
                index += 1
                return
            }
            target = chained
        }
        guard target < track.events.count else {
            index += 1
            return
        }
        repeatReturnIndex = index + 1
        index = target
    }
}

private func tempoAtTick(
    _ tick: Int64,
    startTick: Int64,
    startBPM: Double,
    endTick: Int64,
    targetBPM: Double
) -> Double {
    if endTick <= startTick || tick >= endTick { return targetBPM }
    if tick <= startTick { return startBPM }
    let ratio = Double(tick - startTick) / Double(endTick - startTick)
    return startBPM + (targetBPM - startBPM) * ratio
}

private func resolveTempoModifiers(_ document: RcpDocument, _ modifiers: [TempoModifier]) -> [TempoPoint] {
    var modifiers = modifiers
    modifiers.sort { lhs, rhs in
        lhs.tick != rhs.tick ? lhs.tick < rhs.tick : lhs.order < rhs.order
    }

    var points: [TempoPoint] = []
    var currentBPM = Double(max(1, document.tempoBPM))
    var gradStartTick: Int64 = 0
    var gradEndTick: Int64 = 0
    var gradStartBPM = currentBPM
    var gradTargetBPM = currentBPM
    var generatedThrough: Int64 = 0

    func addGraduation(until limit: Int64) {
        guard gradEndTick > gradStartTick else { return }
        let end = min(limit, gradEndTick)
        if generatedThrough + 1 <= end {
            for tick in (generatedThrough + 1)...end {
                points.append(
                    TempoPoint(
                        tick: tick,
                        order: 0,
                        bpm: max(1.0, tempoAtTick(
                            tick,
                            startTick: gradStartTick,
                            startBPM: gradStartBPM,
                            endTick: gradEndTick,
                            targetBPM: gradTargetBPM
                        ))
                    )
                )
            }
        }
        generatedThrough = max(generatedThrough, end)
    }

    for modifier in modifiers {
        let tick = max(Int64(0), modifier.tick)
        addGraduation(until: tick)
        let currentAtCommand = tempoAtTick(
            tick,
            startTick: gradStartTick,
            startBPM: gradStartBPM,
            endTick: gradEndTick,
            targetBPM: gradTargetBPM
        )
        let target = max(1.0, Double(document.tempoBPM) * (Double(max(1, modifier.ratio)) / 64.0))
        let duration = Int64(tempoGraduationTicks(gradation: modifier.gradation, timeBase: document.timeBase))

        if duration <= 0 {
            points.append(TempoPoint(tick: tick, order: modifier.order, bpm: target))
            currentBPM = target
            gradStartTick = tick
            gradEndTick = tick
            gradStartBPM = target
            gradTargetBPM = target
            generatedThrough = max(generatedThrough, tick)
        } else {
            points.append(TempoPoint(tick: tick, order: modifier.order, bpm: currentAtCommand))
            currentBPM = target
            gradStartTick = tick
            gradEndTick = tick + duration
            gradStartBPM = currentAtCommand
            gradTargetBPM = target
            generatedThrough = tick
        }
    }

    addGraduation(until: gradEndTick)
    points.sort { lhs, rhs in
        lhs.tick != rhs.tick ? lhs.tick < rhs.tick : lhs.order < rhs.order
    }

    var unique: [TempoPoint] = []
    for point in points {
        if let last = unique.last, last.tick == point.tick {
            unique[unique.count - 1] = point
        } else {
            unique.append(point)
        }
    }
    return unique
}

private struct TempoTimeline {
    struct Segment {
        var startTick: Int64
        var startSeconds: Double
        var bpm: Double
    }

    let timeBase: Int
    let initialBPM: Double
    let segments: [Segment]

    init(document: RcpDocument, modifiers: [TempoModifier]) {
        timeBase = max(1, document.timeBase)
        initialBPM = Double(max(1, document.tempoBPM))
        let points = resolveTempoModifiers(document, modifiers)
        var seconds = 0.0
        var startTick: Int64 = 0
        var bpm = initialBPM
        var built: [Segment] = [Segment(startTick: startTick, startSeconds: seconds, bpm: bpm)]
        for point in points {
            guard point.tick >= startTick else { continue }
            seconds += Double(point.tick - startTick) * 60.0 / (bpm * Double(timeBase))
            startTick = point.tick
            bpm = max(1.0, point.bpm)
            built.append(Segment(startTick: startTick, startSeconds: seconds, bpm: bpm))
        }
        segments = built
    }

    func secondsAt(_ tick: Int64) -> Double {
        guard tick > 0 else { return 0 }
        let segment = segment(at: tick)
        return segment.startSeconds
            + Double(tick - segment.startTick) * 60.0 / (segment.bpm * Double(timeBase))
    }

    func finalBPM(at tick: Int64) -> Double {
        guard tick > 0 else { return initialBPM }
        return max(1.0, segment(at: tick).bpm)
    }

    private func segment(at tick: Int64) -> Segment {
        var chosen = segments[0]
        for candidate in segments {
            if candidate.startTick <= tick {
                chosen = candidate
            } else {
                break
            }
        }
        return chosen
    }
}
