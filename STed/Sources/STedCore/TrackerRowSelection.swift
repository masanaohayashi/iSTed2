/// Inclusive row selection, excluding the end-of-track marker.
public struct TrackerRowSelection: Equatable, Sendable {
    public let anchor: Int
    public private(set) var head: Int

    public init(anchor: Int) {
        self.anchor = anchor
        self.head = anchor
    }

    public mutating func move(to row: Int) { head = row }

    public func range(eventCount: Int) -> Range<Int> {
        let lower = min(max(0, min(anchor, head)), eventCount)
        let upper = min(max(0, max(anchor, head) + 1), eventCount)
        return lower..<max(lower, upper)
    }
}
