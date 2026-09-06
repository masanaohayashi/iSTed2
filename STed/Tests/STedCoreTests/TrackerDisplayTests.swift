import XCTest
@testable import STedCore

final class TrackerDisplayTests: XCTestCase {
    func testTrackerInkMatchesOriginalHPrintColors() {
        XCTAssertEqual(
            TrackEvent(command: 60, delay: 48, param1: 36, param2: 100).trackerInk,
            .white
        )
        XCTAssertEqual(
            TrackEvent(command: 64, delay: 0, param1: 36, param2: 100).trackerInk,
            .yellow
        )
        XCTAssertEqual(
            TrackEvent(command: 0xeb, delay: 1, param1: 93, param2: 50).trackerInk,
            .cyan
        )
        XCTAssertEqual(
            TrackEvent(command: 0xfc, delay: 0, param1: 0, param2: 0).trackerInk,
            .cyan
        )
        XCTAssertEqual(TrackEvent.measureLine.trackerInk, .white)
        XCTAssertEqual(
            TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0).trackerInk,
            .white
        )
        XCTAssertEqual(
            TrackEvent(command: 0xf6, delay: 0, param1: 0, param2: 0).trackerInk,
            .white
        )
        XCTAssertEqual(
            TrackEvent(command: 0xf7, delay: 0, param1: 0, param2: 0).trackerInk,
            .white
        )
    }

    func testNoteCellsMatchSTEDLayout() {
        let event = TrackEvent(command: 36, delay: 12, param1: 8, param2: 70)
        let cells = event.trackerCells
        XCTAssertEqual(cells.note, "C 2  36")
        XCTAssertEqual(cells.st, "12")
        XCTAssertEqual(cells.gt, "8")
        XCTAssertEqual(cells.vel, "70")
    }

    func testNoteInputTextMatchesTheOriginalThreeCharacterEditorDisplay() {
        let event = TrackEvent(command: 62, delay: 24, param1: 34, param2: 120)

        XCTAssertEqual(event.noteInputText, "D 4")
    }

    func testGateStarWhenGTExceedsST() {
        let event = TrackEvent(command: 46, delay: 12, param1: 23, param2: 125)
        XCTAssertEqual(event.trackerCells.note, "A#2  46")
        XCTAssertEqual(event.trackerCells.gt, "23*")
    }

    func testZeroGateOrVelocityHidesTheNoteName() {
        let zeroGate = TrackEvent(command: 60, delay: 48, param1: 0, param2: 100)
        let zeroVelocity = TrackEvent(command: 64, delay: 48, param1: 36, param2: 0)

        XCTAssertEqual(zeroGate.trackerCells.note, "     60")
        XCTAssertEqual(zeroVelocity.trackerCells.note, "     64")
    }

    func testChordHidesStepTime() {
        let event = TrackEvent(command: 60, delay: 0, param1: 36, param2: 100)
        XCTAssertEqual(event.trackerCells.st, "")
    }

    func testZeroStepComparesGateWithTheNextPositiveStep() {
        let track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 0, param1: 24, param2: 100),
                TrackEvent(command: 64, delay: 12, param1: 8, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        let rows = track.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)

        XCTAssertEqual(rows[0].gtText, "24*")
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

    func testPaddedNoteRowSharesTheMeasureLineCharacterGrid() {
        let noteRow = TrackerColumn.note("C 3  48")
            + TrackerColumn.value("192")
            + TrackerColumn.value("190")
            + TrackerColumn.value("100")
        let bar = TrackerMeasureLine.text(stepCount: 192)

        XCTAssertEqual(noteRow.count, 25)
        XCTAssertEqual(bar.count, 25)
        XCTAssertEqual(noteRow, "C 3  48   192   190   100")
        XCTAssertEqual(bar, "--------  192 -----------")
        XCTAssertEqual(String(noteRow.dropFirst(10).prefix(3)), "192")
        XCTAssertEqual(String(bar.dropFirst(10).prefix(3)), "192")
    }

    func testMeasureLineShowsThePrecedingMeasureStepCountInTheCenter() {
        let track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 64, delay: 48, param1: 36, param2: 100),
                TrackEvent.measureLine,
                TrackEvent(command: 67, delay: 96, param1: 72, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )
        let rows = track.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)

        XCTAssertTrue(rows[2].isMeasureLine)
        XCTAssertEqual(rows[2].noteText, "--------   96 -----------")
        XCTAssertEqual(rows[2].noteText.count, 25)
        XCTAssertEqual(rows[2].stText, "")
        XCTAssertEqual(rows[2].gtText, "")
        XCTAssertEqual(rows[2].velText, "")
        XCTAssertEqual(track.stepCount(endingAtMeasureLine: 2), 96)
    }

    func testMeasureLineStepCountExpandsRepeatMarkers() {
        let track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 0xf9, delay: 0, param1: 0, param2: 0),
                TrackEvent(command: 60, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 0xf8, delay: 2, param1: 0, param2: 0),
                TrackEvent.measureLine,
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        XCTAssertEqual(track.stepCount(endingAtMeasureLine: 3), 96)
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

    func testCommentUsesTheOriginalFixedWidthRecordBlock() {
        let commentEvents = TrackComment.events(for: "Hello")

        XCTAssertEqual(commentEvents.count, TrackComment.maximumEvents)
        XCTAssertEqual(commentEvents.first?.command, TrackComment.command)
        XCTAssertTrue(commentEvents.dropFirst().allSatisfy { $0.command == TrackComment.continuationCommand })
        XCTAssertEqual(TrackComment.text(from: commentEvents[...]), "Hello")
        XCTAssertEqual(commentEvents[0].param1, 72)
        XCTAssertEqual(commentEvents[0].param2, 101)
    }

    func testCommentRoundTripsShiftJISAndTrimsPadding() {
        let commentEvents = TrackComment.events(for: "日本語")

        XCTAssertEqual(TrackComment.text(from: commentEvents[...]), "日本語")
        XCTAssertEqual(TrackComment.displayText("Hi"), " [Hi                  ]")
        XCTAssertEqual(TrackComment.displayText("日本語"), " [日本語              ]")
    }

    func testCommentIsOneVisibleRowAndPreservesRawSourceRange() {
        let comment = TrackComment.events(for: "note")
        let track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent.defaultNote,
                comment[0], comment[1], comment[2], comment[3], comment[4],
                comment[5], comment[6], comment[7], comment[8], comment[9],
                TrackEvent(command: 64, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        let rows = track.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)

        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[1].sourceRange, 1..<11)
        XCTAssertTrue(rows[1].isComment)
        XCTAssertFalse(rows[1].showsMeasure)
        XCTAssertEqual(rows[1].commentText, "note")
        XCTAssertEqual(rows[1].noteText, " [note                ]")
        XCTAssertEqual(rows[2].sourceRange, 11..<12)
        XCTAssertEqual(rows[2].stepNumber, 2)
        XCTAssertEqual(rows[3].sourceRange, 12..<13)
    }

    func testCommentAtAMeasureBoundaryCarriesTheMeasureMarker() {
        let comment = TrackComment.events(for: "boundary")
        let track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 192, param1: 36, param2: 100),
                comment[0], comment[1], comment[2], comment[3], comment[4],
                comment[5], comment[6], comment[7], comment[8], comment[9],
                TrackEvent(command: 64, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        let rows = track.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)

        XCTAssertEqual(rows[1].time.measure, 2)
        XCTAssertTrue(rows[1].showsMeasure)
        XCTAssertFalse(rows[2].showsMeasure)
    }

    func testMeasureLineStepCountSkipsCommentRecords() {
        let comment = TrackComment.events(for: "after note")
        let track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 36, param2: 100),
                comment[0], comment[1], comment[2], comment[3], comment[4],
                comment[5], comment[6], comment[7], comment[8], comment[9],
                .measureLine,
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        let rows = track.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)

        XCTAssertEqual(rows.last(where: \.isMeasureLine)?.noteText, "--------   48 -----------")
    }
}
