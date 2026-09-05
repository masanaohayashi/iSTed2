public enum FlickDirection: Equatable, Sendable {
    case tap, left, up, right, down
}

public enum EventColumn: Int, CaseIterable, Equatable, Sendable {
    case note, st, gt, vel

    public var numericRange: ClosedRange<Int> {
        switch self {
        case .note, .vel: return 0...127
        case .st, .gt: return 0...255
        }
    }
}

public struct NumericInput: Equatable, Sendable {
    private var digits = ""

    public init() {}

    public mutating func reset() {
        digits = ""
    }

    public mutating func enter(_ digit: Int, range: ClosedRange<Int>) -> Int {
        guard (0...9).contains(digit), range.lowerBound <= range.upperBound else {
            return range.lowerBound
        }

        if digits.isEmpty {
            digits = String(digit)
        } else {
            digits.append(String(digit))
        }

        let enteredValue = Int(digits) ?? Int.max
        return min(range.upperBound, max(range.lowerBound, enteredValue))
    }
}

/// Text entry rules shared by the track editor's keyboard input fields.
///
/// STed2's `sinput` limits the visible edit buffer to four characters. The
/// original numeric fields accept a signed decimal value, while note entry is
/// parsed by `ctc` using the current note as the octave fallback.
public enum TrackerTextInput {
    public static let maximumLength = 4

    public static func normalizedNumeric(_ text: String) -> String {
        var result = ""
        for character in text {
            if result.isEmpty, character == "-" {
                result.append(character)
            } else if let digit = character.wholeNumberValue, (0...9).contains(digit) {
                result.append(Character(String(digit)))
            }

            if result.count == maximumLength {
                break
            }
        }
        return result
    }

    public static func numericValue(
        _ text: String,
        in column: EventColumn
    ) -> Int? {
        let normalized = normalizedNumeric(text)
        guard !normalized.isEmpty, normalized != "-" else { return 0 }
        guard let value = Int(normalized) else { return nil }
        let range = column.numericRange
        return min(range.upperBound, max(range.lowerBound, value))
    }

    public static func normalizedNote(_ text: String) -> String {
        let printable = text.uppercased().unicodeScalars.filter {
            (32...126).contains($0.value)
        }
        return String(String.UnicodeScalarView(printable).prefix(maximumLength))
    }

    /// Parses the note-name syntax used by STed2's `ctc` function.
    ///
    /// `C4` is MIDI note 60. `#` and `+` raise a note, `-` or a following `B`
    /// lower it, and `.` denotes the octave below 0. A note without an octave
    /// uses the octave of `referenceNote`; decimal input is also accepted just
    /// as it is by `ctc`.
    public static func noteNumber(_ text: String, referenceNote: Int = 60) -> Int? {
        let normalized = normalizedNote(text)
        guard !normalized.isEmpty else { return nil }

        let characters = Array(normalized)
        guard let first = characters.first else { return nil }
        let pitchClasses: [Character: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
        ]

        guard var pitchClass = pitchClasses[first] else {
            guard let value = Int(normalized) else { return nil }
            return (0...127).contains(value) ? value : nil
        }

        var octave = referenceNote / 12 - 1
        var index = 1
        if index < characters.count, characters[index] == "B" {
            pitchClass -= 1
            index += 1
        }

        while index < characters.count {
            switch characters[index] {
            case "#", "+": pitchClass += 1
            case "-": pitchClass -= 1
            case ".": octave = -1
            case "<": octave += 1
            case ">": octave -= 1
            case let digit where digit.wholeNumberValue != nil:
                octave = digit.wholeNumberValue ?? octave
            default: break
            }
            index += 1
        }

        let value = (octave + 1) * 12 + pitchClass
        return (0...127).contains(value) ? value : nil
    }
}

public enum TrackerTextInputMode: Equatable, Sendable {
    case numeric
    case note
}

public enum TrackerTextInputCommand: Equatable, Sendable {
    case deleteBackward
    case deleteForward
    case clear
    case moveToBeginning
    case moveToEnd
}

/// The editable buffer and cursor used by an inline tracker cell.
///
/// This deliberately keeps the insertion point separate from the text. The
/// original STed2 `sinput` routine starts with `p = strlen(st)` when editing
/// an existing value, so the character that opened the editor is retained and
/// the next key is inserted after it rather than replacing it.
public struct TrackerTextInputSession: Equatable, Sendable {
    public let mode: TrackerTextInputMode
    public private(set) var text: String
    public private(set) var caretPosition: Int

    public init(mode: TrackerTextInputMode, initialText: String = "") {
        self.mode = mode
        switch mode {
        case .numeric:
            self.text = TrackerTextInput.normalizedNumeric(initialText)
        case .note:
            self.text = TrackerTextInput.normalizedNote(initialText)
        }
        caretPosition = self.text.count
    }

    public mutating func insert(_ input: String) {
        for character in input {
            insert(character)
        }
    }

    public mutating func insert(_ character: Character) {
        guard let character = normalizedCharacter(character) else { return }
        guard text.count < TrackerTextInput.maximumLength else { return }

        var characters = Array(text)
        characters.insert(character, at: caretPosition)
        text = String(characters)
        caretPosition += 1
    }

    public mutating func apply(_ command: TrackerTextInputCommand) {
        switch command {
        case .deleteBackward:
            backspace()
        case .deleteForward:
            delete()
        case .clear:
            clear()
        case .moveToBeginning:
            moveToBeginning()
        case .moveToEnd:
            moveToEnd()
        }
    }

    public mutating func moveLeft() {
        caretPosition = max(0, caretPosition - 1)
    }

    public mutating func moveRight() {
        caretPosition = min(text.count, caretPosition + 1)
    }

    public mutating func moveToBeginning() {
        caretPosition = 0
    }

    public mutating func moveToEnd() {
        caretPosition = text.count
    }

    public mutating func backspace() {
        guard caretPosition > 0 else { return }
        var characters = Array(text)
        characters.remove(at: caretPosition - 1)
        text = String(characters)
        caretPosition -= 1
    }

    public mutating func delete() {
        guard caretPosition < text.count else { return }
        var characters = Array(text)
        characters.remove(at: caretPosition)
        text = String(characters)
    }

    public mutating func clear() {
        text = ""
        caretPosition = 0
    }

    private func normalizedCharacter(_ character: Character) -> Character? {
        switch mode {
        case .numeric:
            if character == "-" {
                guard caretPosition == 0, !text.contains("-") else { return nil }
                return character
            }
            guard let digit = character.wholeNumberValue,
                  (0...9).contains(digit)
            else { return nil }
            return Character(String(digit))
        case .note:
            let normalized = TrackerTextInput.normalizedNote(String(character))
            guard normalized.count == 1 else { return nil }
            return normalized.first
        }
    }
}

public enum TrackEditInput: Equatable, Sendable {
    case digit(Int)
    case pitchClass(Int)
}

public enum FlickPad: Equatable, Sendable {
    case digitsLow
    case digitsHigh
    case notesAC
    case notesDG

    public func value(for direction: FlickDirection) -> TrackEditInput? {
        switch self {
        case .digitsLow:
            switch direction {
            case .tap: return .digit(0)
            case .left: return .digit(1)
            case .up: return .digit(2)
            case .right: return .digit(3)
            case .down: return .digit(4)
            }
        case .digitsHigh:
            switch direction {
            case .tap: return .digit(5)
            case .left: return .digit(6)
            case .up: return .digit(7)
            case .right: return .digit(8)
            case .down: return .digit(9)
            }
        case .notesAC:
            switch direction {
            case .tap: return .pitchClass(0)
            case .left: return .pitchClass(1)
            case .up: return .pitchClass(2)
            case .right, .down: return nil
            }
        case .notesDG:
            switch direction {
            case .tap: return .pitchClass(3)
            case .left: return .pitchClass(4)
            case .up: return .pitchClass(5)
            case .right: return .pitchClass(6)
            case .down: return nil
            }
        }
    }
}

extension TrackEvent {
    public func numericValue(in column: EventColumn) -> Int? {
        switch column {
        case .note:
            guard command < 0x80 else { return nil }
            return Int(command)
        case .st:
            return Int(delay)
        case .gt:
            return Int(param1)
        case .vel:
            return Int(param2)
        }
    }

    public func settingNumericValue(_ value: Int, in column: EventColumn) -> TrackEvent {
        var event = self
        let range = column.numericRange
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        switch column {
        case .note:
            guard event.command < 0x80 else { return event }
            event.command = UInt8(clamped)
        case .st:
            event.delay = UInt8(clamped)
        case .gt:
            event.param1 = UInt8(clamped)
        case .vel:
            event.param2 = UInt8(clamped)
        }
        return event
    }

    public func applying(_ input: TrackEditInput, column: EventColumn) -> TrackEvent {
        var event = self
        switch input {
        case .digit(let digit):
            guard let currentValue = numericValue(in: column) else { return self }
            let nextValue = enterDigit(
                currentValue,
                digit,
                max: column.numericRange.upperBound
            )
            return settingNumericValue(nextValue, in: column)
        case .pitchClass(let classIndex):
            guard event.command < 0x80, (0...6).contains(classIndex) else { return event }
            let pitchClasses = [9, 11, 0, 2, 4, 5, 7]
            let octave = Int(event.command) / 12
            let next = min(127, max(0, octave * 12 + pitchClasses[classIndex]))
            event.command = UInt8(next)
        }
        return event
    }
}

func enterDigit(_ value: Int, _ digit: Int, max: Int) -> Int {
    let next = value * 10 + digit
    return next > max ? digit : next
}
