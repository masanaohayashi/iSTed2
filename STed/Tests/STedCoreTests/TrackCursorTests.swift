import XCTest
@testable import STedCore

final class TrackCursorTests: XCTestCase {
    func testArrowMovementChangesColumnAndReachesEndOfTrackRow() {
        var cursor = TrackCursor()

        cursor.move(.right, rowCount: 3)
        XCTAssertEqual(cursor, TrackCursor(row: 0, column: .st))

        cursor.move(.down, rowCount: 3)
        cursor.move(.down, rowCount: 3)
        cursor.move(.down, rowCount: 3)
        XCTAssertEqual(cursor, TrackCursor(row: 2, column: .st))

        cursor.move(.right, rowCount: 3)
        cursor.move(.right, rowCount: 3)
        cursor.move(.right, rowCount: 3)
        XCTAssertEqual(cursor, TrackCursor(row: 2, column: .vel))

        cursor.move(.up, rowCount: 3)
        cursor.move(.left, rowCount: 3)
        XCTAssertEqual(cursor, TrackCursor(row: 1, column: .gt))
    }
}
