public struct TrackerCells: Equatable, Sendable {
    public var note: String
    public var st: String
    public var gt: String
    public var vel: String

    public init(note: String, st: String, gt: String, vel: String) {
        self.note = note
        self.st = st
        self.gt = gt
        self.vel = vel
    }
}

extension TrackEvent {
    /// The three-character note text shown when STed2 opens note input.
    ///
    /// The original editor keeps the copied note visible while `sinput`'s
    /// edit buffer is still empty. This is intentionally separate from the
    /// full tracker cell, which also contains the numeric note value.
    public var noteInputText: String {
        guard command < 0x80 else { return "" }
        return String(stedNoteLabel(command).prefix(3))
    }

    public var trackerCells: TrackerCells {
        trackerCells(nextEvents: ArraySlice<TrackEvent>())
    }

    func trackerCells(nextEvents: ArraySlice<TrackEvent>) -> TrackerCells {
        if isTerminator {
            return TrackerCells(note: "End of Track", st: "", gt: "", vel: "")
        }
        if command < 0x80 {
            var gt = "\(param1)"
            let comparisonStep: Int?
            if delay > 0 {
                comparisonStep = Int(delay)
            } else {
                comparisonStep = nextEvents.first {
                    $0.command < 0xf7 && $0.delay > 0
                }.map { Int($0.delay) }
            }
            if let comparisonStep, param1 > comparisonStep {
                gt += "*"
            }
            let note = param1 != 0 && param2 != 0
                ? stedNoteLabel(command)
                : "   " + String(format: "%4d", Int(command))
            return TrackerCells(
                note: note,
                st: "\(delay)",
                gt: gt,
                vel: "\(param2)"
            )
        }

        switch command {
        case 0xeb:
            return TrackerCells(
                note: controllerName(param1),
                st: "\(delay)",
                gt: "\(param1 & 127)",
                vel: "\(param2)"
            )
        case 0xee:
            let bend = Int(param1) + Int(param2) * 128 - 8192
            return TrackerCells(
                note: "PITCH",
                st: "\(delay)",
                gt: "",
                vel: "\(bend)"
            )
        case 0xec:
            return TrackerCells(note: "PROGRAM", st: "\(delay)", gt: "\(param1)", vel: "\(param2)")
        case 0xe7:
            return TrackerCells(note: "TEMPO", st: "\(delay)", gt: "\(param1)", vel: "\(param2)")
        case 0xe6:
            return TrackerCells(note: "MIDI CH.", st: "\(delay)", gt: "", vel: "")
        case 0xea:
            return TrackerCells(note: "AFTER C.", st: "\(delay)", gt: "\(param1)", vel: "\(param2)")
        case 0xed:
            return TrackerCells(note: "AFTER K.", st: "\(delay)", gt: "\(param1)", vel: "\(param2)")
        case 0xf8:
            return TrackerCells(note: "]REP", st: "\(delay)", gt: "", vel: "")
        case 0xf9:
            return TrackerCells(note: "REP[", st: "\(delay)", gt: "", vel: "")
        case 0xfc:
            return TrackerCells(note: "=========", st: "", gt: "", vel: "")
        case 0xfd:
            return TrackerCells(note: "----------", st: "", gt: "----", vel: "")
        default:
            return TrackerCells(
                note: String(format: "%02X", command),
                st: "\(delay)",
                gt: "\(param1)",
                vel: "\(param2)"
            )
        }
    }
}

func stedNoteLabel(_ note: UInt8) -> String {
    let names = ["C ", "C#", "D ", "D#", "E ", "F ", "F#", "G ", "G#", "A ", "A#", "B "]
    let pitch = Int(note)
    let octaveIndex = (pitch * 43) >> 9
    let name = names[pitch % 12]
    let octaves = Array(".0123456789")
    let octave = octaves[min(octaveIndex, octaves.count - 1)]
    let number = String(format: "%4d", pitch)
    return "\(name)\(octave)\(number)"
}

private func controllerName(_ number: UInt8) -> String {
    switch number {
    case 1: return "MODULAT"
    case 2: return "BREATH"
    case 4: return "FOOT C."
    case 5: return "PORTA.TM"
    case 7: return "VOLUME"
    case 10: return "PANPOT"
    case 11: return "EXPRESS"
    case 64: return "HOLD1"
    case 65: return "PORTAMEN"
    case 91: return "REVERB"
    case 93: return "CHORUS"
    case 94: return "DELAY"
    default: return "CC\(number)"
    }
}
