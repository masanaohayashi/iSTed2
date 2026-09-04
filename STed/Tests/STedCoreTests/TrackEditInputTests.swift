import XCTest
@testable import STedCore

final class TrackEditInputTests: XCTestCase {
    func testLowDigitPadMapsFlickDirections() {
        XCTAssertEqual(FlickPad.digitsLow.value(for: .tap), .digit(0))
        XCTAssertEqual(FlickPad.digitsLow.value(for: .left), .digit(1))
        XCTAssertEqual(FlickPad.digitsLow.value(for: .up), .digit(2))
        XCTAssertEqual(FlickPad.digitsLow.value(for: .right), .digit(3))
        XCTAssertEqual(FlickPad.digitsLow.value(for: .down), .digit(4))
    }

    func testHighDigitPadMapsFlickDirections() {
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .tap), .digit(5))
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .left), .digit(6))
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .up), .digit(7))
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .right), .digit(8))
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .down), .digit(9))
    }

    func testNotePadsMapAThroughG() {
        XCTAssertEqual(FlickPad.notesAC.value(for: .tap), .pitchClass(0))
        XCTAssertEqual(FlickPad.notesAC.value(for: .left), .pitchClass(1))
        XCTAssertEqual(FlickPad.notesAC.value(for: .up), .pitchClass(2))
        XCTAssertNil(FlickPad.notesAC.value(for: .right))
        XCTAssertNil(FlickPad.notesAC.value(for: .down))

        XCTAssertEqual(FlickPad.notesDG.value(for: .tap), .pitchClass(3))
        XCTAssertEqual(FlickPad.notesDG.value(for: .left), .pitchClass(4))
        XCTAssertEqual(FlickPad.notesDG.value(for: .up), .pitchClass(5))
        XCTAssertEqual(FlickPad.notesDG.value(for: .right), .pitchClass(6))
        XCTAssertNil(FlickPad.notesDG.value(for: .down))
    }

    func testDigitShiftsIntoSelectedField() {
        var event = TrackEvent.defaultNote
        event = event.applying(.digit(4), column: .st)
        event = event.applying(.digit(8), column: .st)
        XCTAssertEqual(event.delay, 48)

        event = event.applying(.digit(1), column: .st)
        event = event.applying(.digit(2), column: .st)
        XCTAssertEqual(event.delay, 12)
    }

    func testPitchClassKeepsOctave() {
        let event = TrackEvent(command: 60, delay: 48, param1: 36, param2: 100)
            .applying(.pitchClass(0), column: .note)
        XCTAssertEqual(event.command, 69)
        XCTAssertEqual(event.trackerCells.note, "A 4  69")
    }

    func testPitchClassIgnoredOnNonNotes() {
        let event = TrackEvent(command: 0xee, delay: 11, param1: 85, param2: 74)
            .applying(.pitchClass(3), column: .note)
        XCTAssertEqual(event.command, 0xee)
    }
}
