import XCTest
@testable import STedCore

final class TrackerRowSelectionTests: XCTestCase {
    func testRangeExpandsShrinksAndReversesAroundAnchor() {
        var selection = TrackerRowSelection(anchor: 3)
        selection.move(to: 5)
        XCTAssertEqual(selection.range(eventCount: 10), 3..<6)
        selection.move(to: 4)
        XCTAssertEqual(selection.range(eventCount: 10), 3..<5)
        selection.move(to: 2)
        XCTAssertEqual(selection.range(eventCount: 10), 2..<4)
        selection.move(to: 10)
        XCTAssertEqual(selection.range(eventCount: 6), 3..<6)
        XCTAssertEqual(selection.range(eventCount: 0), 0..<0)
    }

    func testClipboardRoundTripAndRejectsInvalidData() {
        let events = [TrackEvent.defaultNote, .measureLine,
                      TrackEvent(command: 0xec, delay: 0, param1: 42, param2: 0)]
        XCTAssertEqual(TrackEventClipboard.decode(TrackEventClipboard.encode(events)), events)
        XCTAssertNil(TrackEventClipboard.decode(Data("text".utf8)))
        var truncated = TrackEventClipboard.encode(events)
        truncated.removeLast()
        XCTAssertNil(TrackEventClipboard.decode(truncated))
        XCTAssertNil(TrackEventClipboard.decode(Data([83, 84, 69, 68, 1, 254, 0, 0, 0])))
    }

    func testReplacementInsertionAndDeletePreserveTerminator() {
        let end = TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
        var track = Track(id: 0, number: 1, events: [.defaultNote, .measureLine, .defaultNote, end])
        let program = TrackEvent(command: 0xec, delay: 0, param1: 42, param2: 0)
        track.replaceEvents(in: 0..<2, with: [program])
        XCTAssertEqual(track.events, [program, .defaultNote, end])
        track.replaceEvents(in: 2..<2, with: [program, .measureLine])
        XCTAssertEqual(track.events, [program, .defaultNote, program, .measureLine, end])
        track.replaceEvents(in: 0..<99, with: [])
        XCTAssertEqual(track.events, [end])
        track.replaceEvents(in: 0..<0, with: [.defaultNote, end])
        XCTAssertEqual(track.events, [.defaultNote, end])
    }
}
