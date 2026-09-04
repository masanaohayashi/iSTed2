public enum FlickDirection: Equatable, Sendable {
    case tap, left, up, right, down
}

public enum EventColumn: Int, CaseIterable, Equatable, Sendable {
    case note, st, gt, vel
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
    public func applying(_ input: TrackEditInput, column: EventColumn) -> TrackEvent {
        var event = self
        switch input {
        case .digit(let digit):
            switch column {
            case .note:
                if event.command < 0x80 {
                    event.command = UInt8(enterDigit(Int(event.command), digit, max: 127))
                }
            case .st:
                event.delay = UInt8(enterDigit(Int(event.delay), digit, max: 255))
            case .gt:
                event.param1 = UInt8(enterDigit(Int(event.param1), digit, max: 255))
            case .vel:
                let maxValue = event.command < 0x80 ? 127 : 255
                event.param2 = UInt8(enterDigit(Int(event.param2), digit, max: maxValue))
            }
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
