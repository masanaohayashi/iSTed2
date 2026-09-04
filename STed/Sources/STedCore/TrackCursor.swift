public enum TrackCursorDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

public struct TrackCursor: Equatable, Sendable {
    public var row: Int
    public var column: EventColumn

    public init(row: Int = 0, column: EventColumn = .note) {
        self.row = max(0, row)
        self.column = column
    }

    public mutating func move(_ direction: TrackCursorDirection, rowCount: Int) {
        let lastRow = max(0, rowCount - 1)
        row = min(max(0, row), lastRow)

        switch direction {
        case .up:
            row = max(0, row - 1)
        case .down:
            row = min(lastRow, row + 1)
        case .left:
            guard let previous = EventColumn(rawValue: column.rawValue - 1) else { return }
            column = previous
        case .right:
            guard let next = EventColumn(rawValue: column.rawValue + 1) else { return }
            column = next
        }
    }
}
