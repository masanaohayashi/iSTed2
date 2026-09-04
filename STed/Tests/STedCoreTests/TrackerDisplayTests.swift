import XCTest
@testable import STedCore

final class TrackerDisplayTests: XCTestCase {
    func testNoteCellsMatchSTEDLayout() {
        let event = TrackEvent(command: 36, delay: 12, param1: 8, param2: 70)
        let cells = event.trackerCells
        XCTAssertEqual(cells.note, "C 2  36")
        XCTAssertEqual(cells.st, "12")
        XCTAssertEqual(cells.gt, "8")
        XCTAssertEqual(cells.vel, "70")
    }

    func testGateStarWhenGTExceedsST() {
        let event = TrackEvent(command: 46, delay: 12, param1: 23, param2: 125)
        XCTAssertEqual(event.trackerCells.note, "A#2  46")
        XCTAssertEqual(event.trackerCells.gt, "23*")
    }

    func testChorusUsesControllerName() {
        let event = TrackEvent(command: 0xeb, delay: 1, param1: 93, param2: 50)
        let cells = event.trackerCells
        XCTAssertEqual(cells.note, "CHORUS")
        XCTAssertEqual(cells.st, "1")
        XCTAssertEqual(cells.gt, "93")
        XCTAssertEqual(cells.vel, "50")
    }

    func testPitchShowsSignedBendInVel() {
        let event = TrackEvent(command: 0xee, delay: 11, param1: 85, param2: 74)
        let cells = event.trackerCells
        XCTAssertEqual(cells.note, "PITCH")
        XCTAssertEqual(cells.st, "11")
        XCTAssertEqual(cells.gt, "")
        XCTAssertEqual(cells.vel, "1365")
    }

    func testMeasureBarUsesDashes() {
        let event = TrackEvent(command: 0xfd, delay: 0, param1: 0, param2: 2)
        let cells = event.trackerCells
        XCTAssertEqual(cells.note, "----------")
        XCTAssertEqual(cells.gt, "----")
    }

    func testRowsNumberStepsInsideAMeasure() {
        let track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 64, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 67, delay: 96, param1: 72, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )
        let rows = track.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)
        XCTAssertEqual(rows.map(\.showsMeasure), [true, false, false, false])
        XCTAssertEqual(rows.map(\.stepNumber), [1, 2, 3, nil])
        XCTAssertEqual(rows[0].noteText, "C 4  60")
        XCTAssertEqual(rows[3].noteText, "End of Track")
    }

    func testRowsIncludeEndOfTrackAfterTheLastDataRow() {
        let track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 46, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        let rows = track.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].noteText, "End of Track")
        XCTAssertEqual(rows[1].time.tick, 48)
    }
}
