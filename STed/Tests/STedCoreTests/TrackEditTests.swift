import XCTest
@testable import STedCore

final class TrackEditTests: XCTestCase {
    func testInsertsNoteBeforeTerminator() {
        var track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )
        track.insertEvent(TrackEvent(command: 64, delay: 48, param1: 36, param2: 100), at: 1)
        XCTAssertEqual(track.events.map(\.command), [60, 64, 0xfe])
    }

    func testInsertPastEndGoesBeforeTerminator() {
        var track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent.defaultNote,
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )
        track.insertEvent(TrackEvent(command: 67, delay: 24, param1: 12, param2: 90), at: 99)
        XCTAssertEqual(track.events.map(\.command), [60, 67, 0xfe])
    }

    func testInsertNoteBeforeCopiesThePreviousNote() {
        var track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 46, param2: 100),
                TrackEvent(command: 0xeb, delay: 0, param1: 11, param2: 80),
                TrackEvent(command: 64, delay: 24, param1: 44, param2: 120),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        let inserted = track.insertNoteBefore(at: 2)

        XCTAssertEqual(inserted, track.events[2])
        XCTAssertEqual(track.events[2], track.events[0])
        XCTAssertEqual(track.events.map(\.command), [60, 0xeb, 60, 64, 0xfe])
    }

    func testInsertNoteBeforeUsesC4DefaultsWithoutAnEarlierNote() {
        var track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 0xeb, delay: 12, param1: 7, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        track.insertNoteBefore(at: 0)

        XCTAssertEqual(track.events[0], TrackEvent(command: 60, delay: 48, param1: 46, param2: 100))
    }

    func testInsertMeasureLinePushesTheCurrentRowDown() {
        var track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 64, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        track.insertMeasureLine(at: 1)

        XCTAssertEqual(track.events.map(\.command), [60, 0xfd, 64, 0xfe])
        XCTAssertEqual(track.events[1], TrackEvent.measureLine)
    }

    func testDeleteLeavesTerminator() {
        var track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 64, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )
        track.deleteEvent(at: 0)
        XCTAssertEqual(track.events.map(\.command), [64, 0xfe])
        track.deleteEvent(at: 1)
        XCTAssertEqual(track.events.map(\.command), [64, 0xfe])
        track.deleteEvent(at: 0)
        XCTAssertEqual(track.events.map(\.command), [0xfe])
    }

    func testInsertedNoteChangesPlaybackAndRoundTrips() throws {
        var song = try RCPDecoder.song(from: RCPDemo.middleC)
        song.tracks[0].insertEvent(TrackEvent(command: 64, delay: 48, param1: 36, param2: 100), at: 1)
        XCTAssertEqual(
            try song.playbackSequence().events.map(\.bytes),
            [
                [0x90, 60, 100],
                [0x80, 60, 0],
                [0x90, 64, 100],
                [0x80, 64, 0]
            ]
        )
        let loaded = try RCPDecoder.song(from: RCPEncoder.encode(song))
        XCTAssertEqual(loaded, song)
    }

    func testTrackAttributesClampAndRoundTrip() throws {
        var song = try RCPDecoder.song(from: RCPDemo.phrase)
        song.tracks[0].updateAttributes(
            midiChannel: 16,
            startTick: 40,
            keyShift: -2,
            memo: "lead"
        )
        song.tracks[1].updateAttributes(
            midiChannel: nil,
            startTick: -99,
            keyShift: 63,
            memo: String(repeating: "a", count: 50)
        )
        XCTAssertEqual(song.tracks[0].midiChannel, 16)
        XCTAssertEqual(song.tracks[1].midiChannel, nil)
        XCTAssertEqual(song.tracks[1].startTick, -99)
        XCTAssertEqual(song.tracks[1].memo.count, 36)

        let loaded = try RCPDecoder.song(from: RCPEncoder.encode(song))
        XCTAssertEqual(loaded.tracks[0].midiChannel, 16)
        XCTAssertEqual(loaded.tracks[0].startTick, 40)
        XCTAssertEqual(loaded.tracks[0].keyShift, -2)
        XCTAssertEqual(loaded.tracks[0].memo, "lead")
        XCTAssertEqual(loaded.tracks[1].midiChannel, nil)
        XCTAssertEqual(loaded.tracks[1].keyShift, 63)
        XCTAssertEqual(loaded.tracks[1].memo.count, 36)
    }
}
