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
