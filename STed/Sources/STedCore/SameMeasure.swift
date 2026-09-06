import Foundation

public enum SameMeasureError: String, Error, LocalizedError {
    case invalidTarget = "同じトラック内の、現在位置より前の小節を指定してください。"
    case formatLimit = "RCPの小節参照の範囲（1024小節・約64KB）を超えています。"
    case invalidReference = "小節参照が無効です。"
    public var errorDescription: String? { rawValue }
}

extension Track {
    /// A SAME MEAS record is itself a complete measure boundary.
    public var measureRanges: [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        for index in 0..<terminatorIndex {
            if events[index].command == 0xfd || events[index].command == 0xfc {
                result.append(start..<(index + 1))
                start = index + 1
            }
        }
        if start < terminatorIndex { result.append(start..<terminatorIndex) }
        return result
    }

    public func measureNumber(at row: Int) -> Int {
        measureRanges.firstIndex { $0.contains(row) }.map { $0 + 1 }
            ?? measureRanges.count + 1
    }

    public func sameMeasureTarget(at index: Int) -> Int? {
        guard events.indices.contains(index), events[index].command == 0xfc else { return nil }
        let event = events[index]
        let offset = Int(event.param1 & 0xfc) | Int(event.param2) << 8
        let target = (offset - 44) / 4
        guard offset >= 44, (offset - 44).isMultiple(of: 4), target < index,
              let range = measureRanges.first(where: { $0.lowerBound == target }) else { return nil }
        return range.lowerBound
    }

    private func referenceEvent(target: Int, measure: Int) throws -> TrackEvent {
        let offset = target * 4 + 44
        guard measure >= 1, measure <= 1024, offset < 65536 else { throw SameMeasureError.formatLimit }
        let number = measure - 1
        return TrackEvent(command: 0xfc, delay: UInt8(number & 255),
                          param1: UInt8((offset & 252) | (number >> 8)), param2: UInt8(offset >> 8))
    }

    public func expandedEvents(in range: Range<Int>) throws -> [TrackEvent] {
        var result: [TrackEvent] = []
        for index in range where index >= 0 && index < terminatorIndex {
            if events[index].command == 0xfc {
                guard let target = sameMeasureTarget(at: index),
                      let measure = measureRanges.first(where: { $0.lowerBound == target })
                else { throw SameMeasureError.invalidReference }
                result += try expandedEvents(in: measure)
                if result.last?.command != 0xfd { result.append(.measureLine) }
            } else {
                result.append(events[index])
            }
        }
        return result
    }

    public mutating func insertSameMeasure(at row: Int, referringTo number: Int) throws {
        let row = min(max(0, row), terminatorIndex)
        let measures = measureRanges
        guard number >= 1, number <= measures.count, number < measureNumber(at: row) else {
            throw SameMeasureError.invalidTarget
        }
        let target = measures[number - 1].lowerBound
        let reference = try referenceEvent(target: target, measure: number)
        var replacement: [TrackEvent] = []
        if row > 0, events[row - 1].command < 0xfc { replacement.append(.measureLine) }
        replacement.append(reference)
        let upper = row < terminatorIndex && events[row].command == 0xfc ? row + 1 : row
        replaceEvents(in: row..<upper, with: replacement)
    }

    public mutating func expandSameMeasures(in range: Range<Int>) throws {
        let expanded = try expandedEvents(in: range)
        replaceEvents(in: range, with: expanded)
    }

    public mutating func compressSameMeasures() throws {
        var number = 1
        while number < measureRanges.count {
            let measures = measureRanges
            let range = measures[number]
            if range.count > 1, events[range.upperBound - 1].command == 0xfd {
                let content = try expandedEvents(in: range)
                for earlier in 0..<number {
                    if try expandedEvents(in: measures[earlier]) == content {
                        let event = try referenceEvent(target: measures[earlier].lowerBound, measure: earlier + 1)
                        replaceEvents(in: range, with: [event])
                        break
                    }
                }
            }
            number += 1
        }
    }

    /// Rebuild packed offsets after edits. If a referenced measure disappears,
    /// materialize its dependents using the pre-edit content.
    mutating func replacePreservingReferences(in range: Range<Int>, with replacement: [TrackEvent]) {
        let old = self
        let measures = old.measureRanges
        var nodes: [(event: TrackEvent, original: Int?)] = []
        nodes += events[..<range.lowerBound].enumerated().map { ($0.element, $0.offset) }
        nodes += replacement.filter { !$0.isTerminator }.map { (event: $0, original: Optional<Int>.none) }
        nodes += events[range.upperBound...].enumerated().map { ($0.element, $0.offset + range.upperBound) }
        var index = 0
        while index < nodes.count {
            if nodes[index].event.command == 0xfc, let original = nodes[index].original,
               let target = old.sameMeasureTarget(at: original),
               let source = measures.first(where: { $0.lowerBound == target }) {
                let surviving = nodes.firstIndex { node in node.original.map(source.contains) ?? false }
                if let surviving, surviving < index {
                    var start = surviving
                    while start > 0 && nodes[start - 1].event.command != 0xfd && nodes[start - 1].event.command != 0xfc {
                        start -= 1
                    }
                    let number = nodes[..<start].filter { $0.event.command == 0xfd || $0.event.command == 0xfc }.count + 1
                    if let reference = try? referenceEvent(target: start, measure: number) {
                        nodes[index].event = reference
                    } else if let expanded = try? old.expandedEvents(in: source) {
                        nodes.replaceSubrange(index...index, with: expanded.map { (event: $0, original: Optional<Int>.none) })
                    }
                } else if let expanded = try? old.expandedEvents(in: source) {
                    nodes.replaceSubrange(index...index, with: expanded.map { (event: $0, original: Optional<Int>.none) })
                }
            }
            index += 1
        }
        events = nodes.map(\.event)
        if events.last?.isTerminator != true {
            events.append(TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0))
        }
    }
}
