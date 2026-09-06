public struct SpecialControllerCode: Equatable, Sendable {
    public var command: UInt8
    public var control: Int

    public init(command: UInt8, control: Int) {
        self.command = command
        self.control = control
    }
}

public enum SpecialControllerField: Equatable, Sendable {
    case stepTime
    case gateTime(ClosedRange<Int>)
    case velocity(ClosedRange<Int>)
    case pitchBend
    case midiChannel
}

public enum SpecialControllerSymbolInputAction: Equatable, Sendable {
    case openSelector
    case commitSymbol
}

public struct SpecialControllerSelectorItem: Equatable, Sendable {
    public var symbol: String
    public var name: String
    public var comment: String

    public init(symbol: String, name: String, comment: String) {
        self.symbol = symbol
        self.name = name
        self.comment = comment
    }
}

/// STed2 `spc_code` / `spcon` / `spc_select`.
public enum SpecialController {
    public static let selectorItems: [SpecialControllerSelectorItem] = {
        let symbols: [String] = [
            "G", "M", "T", "P", "C", "K", "L", "D", "V", "N", "E", "H", "A", "",
            "X", "B", "R", "I", "EM", "EL", "NM", "NL", "RM", "RL"
        ]
        let names: [String] = [
            "PROGRAM", "MIDI CH.", "TEMPO", "PITCH", "AFTER C.", "AFTER K.", "CONTROL",
            "MODULAT", "VOLUME", "PANPOT", "EXPRESS", "HOLD1", "RES.ALL", "",
            "Tr.Exclu", "Rol.Base", "Rol.Para", "Rol.Dev#",
            "DATA MSB", "DATA LSB", "NRPN MSB", "NRPN LSB", "RPN MSB", "RPN LSB"
        ]
        let comments: [String] = [
            "PROGRAM CHANGE",
            "MIDI CHANNEL CHANGE",
            "TEMPO CHANGE",
            "PITCH BEND CHANGE",
            "AFTER TOUCH(CH.)",
            "AFTER TOUCH(POLY)",
            "CONTROL CHANGE",
            "MODULATION",
            "VOLUME",
            "PANPOT",
            "EXPRESSION",
            "HOLD1(DAMPER PEDAL)",
            "RESET ALL CONTROLLERS",
            "",
            "Track Exclusive",
            "Roland Base Address",
            "Roland Offset Add. & Para.",
            "Roland Device No. & Model ID",
            "Data Entry(MSB)",
            "Data Entry(LSB)",
            "Non Registerd Parameter MSB",
            "Non Registerd Parameter LSB",
            "Registerd Parameter MSB",
            "Registerd Parameter LSB"
        ]
        return zip(symbols, zip(names, comments)).map { symbol, rest in
            SpecialControllerSelectorItem(symbol: symbol, name: rest.0, comment: rest.1)
        }
    }()

    public static func code(from symbol: String) -> SpecialControllerCode? {
        var characters = Array(symbol.uppercased())
        if characters.first == "/" {
            characters.removeFirst()
        }
        guard let rawA = characters.first else { return nil }
        let a = rawA.asciiValue ?? 0
        let b = characters.count > 1 ? (characters[1].asciiValue ?? 0) : 0
        var command: UInt8 = 0xeb
        var control = -1

        if a == UInt8(ascii: "@") {
            control = 0
            if b == UInt8(ascii: "@") || b == UInt8(ascii: "L") {
                control = 32
            }
        }
        if a == UInt8(ascii: "D") { control = 1 }
        if a == UInt8(ascii: "V") { control = 7 }
        if a == UInt8(ascii: "N") { control = 10 }
        if a == UInt8(ascii: "E") { control = 11 }
        if a == UInt8(ascii: "H") { control = 64 }
        if a == UInt8(ascii: "A") { control = 121 }

        if a == UInt8(ascii: "F"), (UInt8(ascii: "1")...UInt8(ascii: "5")).contains(b) {
            control = Int(b - UInt8(ascii: "1")) + 91
        }
        if a == UInt8(ascii: "P") {
            if b == UInt8(ascii: "T") { control = 5 }
            if b == UInt8(ascii: "O") { control = 65 }
            if b == UInt8(ascii: "C") { control = 84 }
        }
        if a == UInt8(ascii: "S") {
            if b == UInt8(ascii: "S") { control = 66 }
            if b == UInt8(ascii: "T") { control = 67 }
        }
        if a == UInt8(ascii: "E") {
            if b == UInt8(ascii: "M") { control = 6 }
            if b == UInt8(ascii: "L") { control = 38 }
        }
        if a == UInt8(ascii: "N") {
            if b == UInt8(ascii: "M") { control = 99 }
            if b == UInt8(ascii: "L") { control = 98 }
        }
        if a == UInt8(ascii: "R") {
            if b == UInt8(ascii: "M") { control = 101 }
            if b == UInt8(ascii: "L") { control = 100 }
        }
        if a == UInt8(ascii: "B"), b == UInt8(ascii: "R") {
            control = 2
        }
        if a == UInt8(ascii: "R"), b == UInt8(ascii: "S") { control = 71 }
        if a == UInt8(ascii: "R"), b == UInt8(ascii: "T") { control = 72 }
        if a == UInt8(ascii: "A"), b == UInt8(ascii: "T") { control = 73 }
        if a == UInt8(ascii: "C"), b == UInt8(ascii: "O") { control = 74 }

        if control < 0 {
            command = 0
            if a == UInt8(ascii: "U"), (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(b) {
                command = 0x90 + (b - UInt8(ascii: "0"))
            }
            if a == UInt8(ascii: "X") { command = 0x98 }
            if a == UInt8(ascii: "B") { command = 0xdd }
            if a == UInt8(ascii: "R") { command = 0xde }
            if a == UInt8(ascii: "I") { command = 0xdf }
            if a == UInt8(ascii: "T") { command = 0xe7 }
            if a == UInt8(ascii: "C") { command = 0xea }
            if a == UInt8(ascii: "S") {
                if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b) {
                    command = 0xc0 + (b - UInt8(ascii: "0"))
                }
                if (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(b) {
                    command = 0xca + (b - UInt8(ascii: "A"))
                }
                if b == UInt8(ascii: "4") {
                    command = 0xdc
                }
            }
            if a == UInt8(ascii: "L") {
                command = 0xeb
                if characters.count > 1 {
                    control = atoi(String(characters.dropFirst()))
                }
            }
            if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(a) {
                command = 0xeb
                control = atoi(String(characters))
                if control > 127 {
                    control = -1
                }
            }
            if a == UInt8(ascii: "G") {
                if b == UInt8(ascii: "@") || b == UInt8(ascii: "M") {
                    command = 0xe2
                    if characters.count > 2 {
                        control = atoi(String(characters.dropFirst(2)))
                    }
                } else {
                    command = 0xec
                    if characters.count > 1 {
                        control = atoi(String(characters.dropFirst()))
                    }
                }
            }
            if a == UInt8(ascii: "K") { command = 0xed }
            if a == UInt8(ascii: "P") { command = 0xee }
            if a == UInt8(ascii: "M") { command = 0xe6 }
        }

        guard command != 0 else { return nil }
        return SpecialControllerCode(command: command, control: control)
    }

    public static func makeEvent(
        _ code: SpecialControllerCode,
        previousEvents: ArraySlice<TrackEvent>,
        trackMIDIChannel: Int?
    ) -> TrackEvent {
        var event = TrackEvent.specialControllerPlaceholder
        var control = code.control
        let command = code.command

        if command == 0xe2 || command == 0xec {
            event.param1 = UInt8(clamping: previousProgramNumber(in: previousEvents))
        }
        if control > 127 {
            control = 127
        }
        if command == 0xeb {
            event.param1 = 128
        }
        if control >= 0 {
            event.param1 = UInt8(clamping: control)
        }
        if command == 0xee {
            event.param1 = 0
            event.param2 = 64
        }
        if command == 0xe6 {
            event.param1 = UInt8(clamping: previousMIDIChannel(
                in: previousEvents,
                trackMIDIChannel: trackMIDIChannel
            ))
        }
        event.command = command
        return event
    }

    public static func fields(for code: SpecialControllerCode) -> [SpecialControllerField] {
        let command = code.command
        let control = code.control
        var fields: [SpecialControllerField] = [.stepTime]

        if command == 0xee {
            fields.append(.pitchBend)
        }

        if (command == 0xec || command == 0xe2) && control < 0 {
            fields.append(.gateTime(0...127))
        }

        if command != 0xee && command != 0xec && command != 0xe2 && control < 0 {
            if command == 0xe6 {
                fields.append(.midiChannel)
            } else if command == 0xe7 {
                fields.append(.gateTime(1...255))
            } else {
                fields.append(.gateTime(0...127))
            }
        }

        if command != 0xee && command != 0xed && command != 0xec && command != 0xe6 {
            if command == 0xe7 {
                fields.append(.velocity(0...255))
            } else {
                fields.append(.velocity(0...127))
            }
        }

        return fields
    }

    public static func pitchBendEvent(delay: UInt8, bend: Int) -> TrackEvent {
        let centered = min(16383, max(0, bend + 8192))
        return TrackEvent(
            command: 0xee,
            delay: delay,
            param1: UInt8(centered & 0x7f),
            param2: UInt8((centered >> 7) & 0x7f)
        )
    }

    public static func pitchValue(param1: UInt8, param2: UInt8) -> Int {
        Int(param1) + Int(param2) * 128 - 8192
    }

    public static func nextSelectorIndex(from index: Int, movingDown: Bool) -> Int {
        let count = selectorItems.count
        var next = index
        repeat {
            next = (next + (movingDown ? 1 : count - 1)) % count
        } while selectorItems[next].symbol.isEmpty
        return next
    }

    public static func selectorSymbol(at index: Int, confirming: Bool) -> String? {
        guard confirming,
              selectorItems.indices.contains(index)
        else { return nil }
        let symbol = selectorItems[index].symbol
        return symbol.isEmpty ? nil : symbol
    }

    public static func symbolInputAction(forDownArrow: Bool) -> SpecialControllerSymbolInputAction {
        forDownArrow ? .openSelector : .commitSymbol
    }

    public static func column(for field: SpecialControllerField) -> EventColumn {
        switch field {
        case .stepTime:
            return .st
        case .gateTime, .midiChannel:
            return .gt
        case .velocity, .pitchBend:
            return .vel
        }
    }

    public static func numericRange(for field: SpecialControllerField) -> ClosedRange<Int> {
        switch field {
        case .stepTime:
            return 0...255
        case .gateTime(let range), .velocity(let range):
            return range
        case .pitchBend:
            return -8192...8191
        case .midiChannel:
            return 0...32
        }
    }

    private static func previousProgramNumber(in events: ArraySlice<TrackEvent>) -> Int {
        for event in events.reversed() {
            if event.command == 0xec || event.command == 0xe2 {
                return Int(event.param1)
            }
        }
        return 0
    }

    private static func previousMIDIChannel(
        in events: ArraySlice<TrackEvent>,
        trackMIDIChannel: Int?
    ) -> Int {
        for event in events.reversed() {
            if event.command == 0xe6 {
                return Int(event.param1)
            }
            if event.command == 0xec {
                return Int(event.param2)
            }
        }
        return trackMIDIChannel ?? 0
    }

    private static func atoi(_ text: String) -> Int {
        var value = 0
        var sawDigit = false
        for character in text {
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else {
                break
            }
            sawDigit = true
            value = value * 10 + digit
        }
        return sawDigit ? value : 0
    }
}
