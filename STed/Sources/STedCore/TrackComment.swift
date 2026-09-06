import Foundation

/// The comment record used by STed2 tracks.
///
/// RCP stores a comment as a `0xf6` record followed by zero or more `0xf7`
/// continuation records. Each record carries two Shift-JIS bytes, so the
/// editor's 20-byte buffer occupies ten four-byte records.
public enum TrackComment {
    public static let command: UInt8 = 0xf6
    public static let continuationCommand: UInt8 = 0xf7
    public static let maximumBytes = 20
    public static let bytesPerEvent = 2
    public static let maximumEvents = maximumBytes / bytesPerEvent

    /// Keeps only printable characters that the PC-98 Shift-JIS comment
    /// buffer can represent, without exceeding its byte capacity.
    public static func normalizedText(_ text: String) -> String {
        var result = ""
        var byteCount = 0
        for character in text {
            guard character.unicodeScalars.allSatisfy({ scalar in
                scalar.value >= 0x20 && scalar.value != 0x7f
            }),
                  let encoded = String(character).data(using: .shiftJIS)
            else { continue }
            guard byteCount + encoded.count <= maximumBytes else { break }
            result.append(character)
            byteCount += encoded.count
        }
        return result
    }

    /// Converts text to the fixed-width byte buffer used by the original
    /// `comment_inp` routine. Characters that cannot be represented in
    /// Shift-JIS are removed rather than writing malformed record pairs.
    public static func events(for text: String) -> [TrackEvent] {
        let normalized = normalizedText(text)
        var bytes = Array(normalized.data(using: .shiftJIS) ?? Data())
        bytes += repeatElement(0x20, count: maximumBytes - bytes.count)

        return stride(from: 0, to: maximumBytes, by: bytesPerEvent).enumerated().map {
            let offset = $0.element
            return TrackEvent(
                command: $0.offset == 0 ? command : continuationCommand,
                delay: 0,
                param1: bytes[offset],
                param2: bytes[offset + 1]
            )
        }
    }

    /// Decodes a contiguous comment record block, trimming the spaces that
    /// STed2 uses to fill the edit buffer.
    public static func text(from events: ArraySlice<TrackEvent>) -> String {
        guard let first = events.first, first.command == command else { return "" }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(events.count * bytesPerEvent)
        for (index, event) in events.enumerated() {
            guard index == 0 || event.command == continuationCommand else { break }
            bytes.append(event.param1)
            bytes.append(event.param2)
        }

        while let last = bytes.last, last == 0 || last == 0x20 || last == 0x09 {
            bytes.removeLast()
        }
        return String(bytes: bytes, encoding: .shiftJIS)
            ?? String(bytes: bytes, encoding: .utf8)
            ?? ""
    }

    /// The byte range occupied by the comment containing `index`.
    public static func range(in events: [TrackEvent], startingAt index: Int) -> Range<Int>? {
        guard events.indices.contains(index) else { return nil }
        var start = index
        if events[start].command == continuationCommand {
            while start > 0, events[start - 1].command == continuationCommand {
                start -= 1
            }
            guard start > 0, events[start - 1].command == command else { return nil }
            start -= 1
        }
        guard events[start].command == command else { return nil }
        var end = start + 1
        while end < events.count, events[end].command == continuationCommand {
            end += 1
        }
        return start..<end
    }

    /// Text suitable for the tracker row. The brackets and 20-byte field
    /// mirror STed2's `trk_dis` output.
    public static func displayText(_ text: String) -> String {
        let normalized = normalizedText(text)
        let byteCount = normalized.data(using: .shiftJIS)?.count ?? 0
        let padded = normalized + String(repeating: " ", count: max(0, maximumBytes - byteCount))
        return " [\(padded)]"
    }
}

extension TrackEvent {
    public var isCommentStart: Bool { command == TrackComment.command }
    public var isCommentContinuation: Bool { command == TrackComment.continuationCommand }
}
