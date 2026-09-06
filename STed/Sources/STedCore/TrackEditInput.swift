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
    public static let symbolMaximumLength = 5

    public static func maximumLength(for mode: TrackerTextInputMode) -> Int {
        switch mode {
        case .numeric, .note:
            return maximumLength
        case .symbol, .pitch:
            return symbolMaximumLength
        }
    }

    public static func normalizedNumeric(
        _ text: String,
        maximumLength: Int = maximumLength
    ) -> String {
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
        numericValue(text, in: column.numericRange)
    }

    public static func numericValue(
        _ text: String,
        in range: ClosedRange<Int>,
        maximumLength: Int = maximumLength
    ) -> Int? {
        let normalized = normalizedNumeric(text, maximumLength: maximumLength)
        guard !normalized.isEmpty, normalized != "-" else { return 0 }
        guard let value = Int(normalized) else { return nil }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    public static func normalizedNote(_ text: String) -> String {
        let printable = text.uppercased().unicodeScalars.filter {
            (32...126).contains($0.value)
        }
        return String(String.UnicodeScalarView(printable).prefix(maximumLength))
    }

    public static func normalizedSymbol(_ text: String) -> String {
        let printable = text.uppercased().unicodeScalars.filter {
            (32...126).contains($0.value)
        }
        return String(String.UnicodeScalarView(printable).prefix(symbolMaximumLength))
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
    case symbol
    case pitch
}

public enum TrackerTextInputCommand: Equatable, Sendable {
    case deleteBackward
    case deleteForward
    case clear
    case moveToBeginning
    case moveToEnd
}

/// Keys that STed2's main track editor loop treats as line deletion (`DEL`).
///
/// SwiftUI can report the Mac Delete key as `.delete`, `.deleteForward`,
/// or a control character, so the editor matches every form.
public enum TrackerEditorKey: Equatable, Sendable {
    case delete
    case deleteForward
    case backspaceCharacter
    case forwardDeleteCharacter
    case insertMeasureLine
    case insertSpecialController

    public init?(characters: String) {
        switch characters {
        case "\u{8}":
            self = .backspaceCharacter
        case "\u{7f}":
            self = .forwardDeleteCharacter
        case "=", "*":
            self = .insertMeasureLine
        case "/":
            self = .insertSpecialController
        default:
            return nil
        }
    }
}

public enum TrackerEditorCommand: Equatable, Sendable {
    case deleteSelectedRow
    case insertMeasureLine
    case insertSpecialController
}

/// What A–G does on the current tracker row, matching STed2 `kc>='A' && kc<='G'`.
public enum TrackerInlineCancelAction: Equatable, Sendable {
    case discardEdits
    case deleteInsertedStep

    public static func forInsertedNote(_ isInsertedNote: Bool) -> TrackerInlineCancelAction {
        isInsertedNote ? .deleteInsertedStep : .discardEdits
    }

    public static func forInsertedSpecial(_ isInsertedSpecial: Bool) -> TrackerInlineCancelAction {
        forInsertedNote(isInsertedSpecial)
    }
}

public enum TrackerNoteKeyAction: Equatable, Sendable {
    case editExisting
    case insertNew
    case ignore

    public static func forCommand(_ command: UInt8) -> TrackerNoteKeyAction {
        if command < 0x80 {
            return .editExisting
        }
        if command > 0xfb {
            return .insertNew
        }
        return .ignore
    }
}

/// Digit/`sinput` targets for an existing tracker row, matching EDIT.C 0–9.
public enum TrackerNumericEditAction: Equatable, Sendable {
    case ignore
    case edit(EventColumn)
    case editPitchBend

    public static func forCommand(_ command: UInt8, column: EventColumn) -> TrackerNumericEditAction {
        if command == 0xeb, column == .note {
            return .edit(.gt)
        }
        if command < 0x80 {
            return .edit(column)
        }
        if command == 0xee, column == .gt || column == .vel {
            return .editPitchBend
        }
        if command == 0xec, column == .gt || column == .vel {
            return .edit(.gt)
        }
        if column == .note {
            return .ignore
        }
        if command < 0xf0 || command == 0xf8 || command == 0xfc {
            if command == 0xfc {
                return .edit(.st)
            }
            return .edit(column)
        }
        return .ignore
    }

    public static func range(command: UInt8, column: EventColumn) -> ClosedRange<Int> {
        if command == 0xee, column == .gt || column == .vel {
            return -8192...8191
        }
        if command < 0x80 {
            return column.numericRange
        }
        if command == 0xe7 || column == .st {
            return 0...255
        }
        return 0...127
    }

    public var column: EventColumn {
        switch self {
        case .ignore:
            return .note
        case .edit(let column):
            return column
        case .editPitchBend:
            return .vel
        }
    }
}

public enum TrackerEditorKeyMap {
    public static func command(
        for key: TrackerEditorKey,
        isInlineEditing: Bool
    ) -> TrackerEditorCommand? {
        guard !isInlineEditing else { return nil }
        switch key {
        case .delete, .deleteForward, .backspaceCharacter, .forwardDeleteCharacter:
            return .deleteSelectedRow
        case .insertMeasureLine:
            return .insertMeasureLine
        case .insertSpecialController:
            return .insertSpecialController
        }
    }
}

/// The editable buffer and cursor used by an inline tracker cell.
///
/// This deliberately keeps the insertion point separate from the text. The
/// original STed2 `sinput` routine starts with `p = strlen(st)` when editing
/// an existing value, so the character that opened the editor is retained and
/// the next key is inserted after it rather than replacing it. macOS column
/// navigation additionally uses `isAllSelected` to replace the destination
/// value with the next valid character.
public struct TrackerTextInputSession: Equatable, Sendable {
    public let mode: TrackerTextInputMode
    public private(set) var text: String
    public private(set) var caretPosition: Int
    public private(set) var isAllSelected: Bool

    public init(
        mode: TrackerTextInputMode,
        initialText: String = "",
        selectAll: Bool = false
    ) {
        self.mode = mode
        switch mode {
        case .numeric:
            self.text = TrackerTextInput.normalizedNumeric(initialText)
        case .note:
            self.text = TrackerTextInput.normalizedNote(initialText)
        case .symbol:
            self.text = TrackerTextInput.normalizedSymbol(initialText)
        case .pitch:
            self.text = TrackerTextInput.normalizedNumeric(initialText, maximumLength: TrackerTextInput.symbolMaximumLength)
        }
        caretPosition = self.text.count
        isAllSelected = selectAll && !self.text.isEmpty
    }

    public mutating func insert(_ input: String) {
        for character in input {
            insert(character)
        }
    }

    public mutating func insert(_ character: Character) {
        guard let character = normalizedCharacter(character) else { return }

        if isAllSelected {
            text = ""
            caretPosition = 0
            isAllSelected = false
        }

        guard text.count < TrackerTextInput.maximumLength(for: mode) else { return }

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
        isAllSelected = false
        caretPosition = max(0, caretPosition - 1)
    }

    public mutating func moveRight() {
        isAllSelected = false
        caretPosition = min(text.count, caretPosition + 1)
    }

    public mutating func moveToBeginning() {
        isAllSelected = false
        caretPosition = 0
    }

    public mutating func moveToEnd() {
        isAllSelected = false
        caretPosition = text.count
    }

    public mutating func backspace() {
        if isAllSelected {
            clear()
            return
        }
        guard caretPosition > 0 else { return }
        var characters = Array(text)
        characters.remove(at: caretPosition - 1)
        text = String(characters)
        caretPosition -= 1
    }

    public mutating func delete() {
        if isAllSelected {
            clear()
            return
        }
        guard caretPosition < text.count else { return }
        var characters = Array(text)
        characters.remove(at: caretPosition)
        text = String(characters)
    }

    public mutating func clear() {
        text = ""
        caretPosition = 0
        isAllSelected = false
    }

    private func normalizedCharacter(_ character: Character) -> Character? {
        switch mode {
        case .numeric, .pitch:
            if character == "-" {
                let validationText = isAllSelected ? "" : text
                let validationCaret = isAllSelected ? 0 : caretPosition
                guard validationCaret == 0, !validationText.contains("-") else {
                    return nil
                }
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
        case .symbol:
            let normalized = TrackerTextInput.normalizedSymbol(String(character))
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

    public func editorValue(for action: TrackerNumericEditAction) -> Int? {
        switch action {
        case .ignore:
            return nil
        case .edit(let column):
            if command == 0xeb, column == .gt {
                return Int(param1 & 127)
            }
            return numericValue(in: column)
        case .editPitchBend:
            return SpecialController.pitchValue(param1: param1, param2: param2)
        }
    }

    public func settingNumericValue(_ value: Int, in column: EventColumn) -> TrackEvent {
        settingEditorValue(value, action: .edit(column))
    }

    public func settingEditorValue(_ value: Int, action: TrackerNumericEditAction) -> TrackEvent {
        switch action {
        case .ignore:
            return self
        case .editPitchBend:
            return SpecialController.pitchBendEvent(delay: delay, bend: value)
        case .edit(let column):
            var event = self
            let range = TrackerNumericEditAction.range(command: command, column: column)
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
    }

    public func applying(_ input: TrackEditInput, column: EventColumn) -> TrackEvent {
        var event = self
        switch input {
        case .digit(let digit):
            let action = TrackerNumericEditAction.forCommand(command, column: column)
            guard let currentValue = editorValue(for: action) else { return self }
            let range = TrackerNumericEditAction.range(command: command, column: action.column)
            let nextValue = enterDigit(currentValue, digit, max: range.upperBound)
            return settingEditorValue(nextValue, action: action)
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
