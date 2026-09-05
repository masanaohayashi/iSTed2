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
        XCTAssertEqual(cursor, TrackCursor(row: 2, column: .note))

        cursor.move(.up, rowCount: 3)
        cursor.move(.left, rowCount: 3)
        XCTAssertEqual(cursor, TrackCursor(row: 0, column: .vel))
    }

    func testRightFromVelocityWrapsToNoteOnNextRow() {
        var cursor = TrackCursor(row: 1, column: .vel)

        cursor.move(.right, rowCount: 3)

        XCTAssertEqual(cursor, TrackCursor(row: 2, column: .note))
    }

    func testLeftFromNoteWrapsToVelocityOnPreviousRow() {
        var cursor = TrackCursor(row: 1, column: .note)

        cursor.move(.left, rowCount: 3)

        XCTAssertEqual(cursor, TrackCursor(row: 0, column: .vel))
    }
}
