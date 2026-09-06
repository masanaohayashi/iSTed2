import Foundation

/// Four-byte RCP events with a version header; track terminators are never copied.
public enum TrackEventClipboard {
    public static let typeIdentifier = "local.sted.track-events"
    public static func encode(_ events: [TrackEvent]) -> Data {
        var bytes: [UInt8] = [83, 84, 69, 68, 1]
        for event in events where !event.isTerminator {
            bytes += [event.command, event.delay, event.param1, event.param2]
        }
        return Data(bytes)
    }
    public static func decode(_ data: Data) -> [TrackEvent]? {
        let bytes = Array(data)
        guard bytes.count > 5, bytes.prefix(5) == [83, 84, 69, 68, 1],
              (bytes.count - 5).isMultiple(of: 4) else { return nil }
        var events: [TrackEvent] = []
        for index in stride(from: 5, to: bytes.count, by: 4) {
            let event = TrackEvent(command: bytes[index], delay: bytes[index + 1],
                                   param1: bytes[index + 2], param2: bytes[index + 3])
            guard !event.isTerminator else { return nil }
            events.append(event)
        }
        return events
    }
}
