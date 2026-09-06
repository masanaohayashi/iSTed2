import XCTest
@testable import STedCore

final class SameMeasureTests: XCTestCase {
    let end = TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
    var note: TrackEvent { TrackEvent(command: 60, delay: 192, param1: 24, param2: 100) }
    func fixture() -> Track { Track(id: 0, number: 1, events: [note, .measureLine, end]) }

    func testAliasFollowsEditsAndSchedulesAWholeMeasure() throws {
        var track = fixture()
        try track.insertSameMeasure(at: 2, referringTo: 1)
        XCTAssertEqual(track.events.map(\.command), [60, 0xfd, 0xfc, 0xfe])
        XCTAssertEqual(track.sameMeasureTarget(at: 2), 0)
        track.events[0].command = 64
        XCTAssertEqual(try track.expandedEvents(in: 2..<3), [track.events[0], .measureLine])
        let song = Song(title: "same", timeBase: 48, tempoBPM: 120, beatNumerator: 4, beatDenominator: 4, tracks: [track])
        let sequence = try song.playbackSequence()
        XCTAssertEqual(sequence.events.filter { $0.bytes.first == 0x90 }.map(\.ticks), [0, 192])
        XCTAssertEqual(track.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4).last?.time.tick, 384)
        let decoded = try RCPDecoder.song(from: RCPEncoder.encode(song))
        XCTAssertEqual(try decoded.playbackSequence().events, sequence.events)
    }

    func testReferenceOffsetsFollowInsertAndPartialDeletion() throws {
        var track = fixture()
        try track.insertSameMeasure(at: 2, referringTo: 1)
        track.insertEvent(note, at: 0)
        XCTAssertEqual(track.sameMeasureTarget(at: 3), 0)
        XCTAssertEqual(try track.expandedEvents(in: 3..<4).count, 3)
        track.deleteEvent(at: 0)
        XCTAssertEqual(track.sameMeasureTarget(at: 2), 0)
        XCTAssertEqual(try track.expandedEvents(in: 2..<3), [note, .measureLine])
        track.insertMeasureLine(at: 0)
        XCTAssertEqual(track.sameMeasureTarget(at: 3), 1)
        XCTAssertEqual(track.events[3].delay, 1)
    }

    func testDeletedSourceMaterializesDependentMeasures() throws {
        var track = fixture()
        try track.insertSameMeasure(at: 2, referringTo: 1)
        try track.insertSameMeasure(at: 3, referringTo: 2)
        track.replaceEvents(in: 0..<2, with: [])
        XCTAssertEqual(track.events, [note, .measureLine, note, .measureLine, end])
    }

    func testCompressExpandAndCopyRoundTrip() throws {
        var track = Track(id: 0, number: 1, events: [note, .measureLine, note, .measureLine, note, .measureLine, end])
        let original = track.events
        try track.compressSameMeasures()
        XCTAssertEqual(track.events.map(\.command), [60, 0xfd, 0xfc, 0xfc, 0xfe])
        let copied = try track.expandedEvents(in: 2..<4)
        XCTAssertEqual(copied, [note, .measureLine, note, .measureLine])
        try track.expandSameMeasures(in: 0..<track.terminatorIndex)
        XCTAssertEqual(track.events, original)
    }

    func testForwardAndInvalidReferencesAreRejectedWithoutChanges() throws {
        var track = fixture()
        let original = track
        XCTAssertThrowsError(try track.insertSameMeasure(at: 0, referringTo: 1))
        XCTAssertThrowsError(try track.insertSameMeasure(at: 2, referringTo: 2))
        XCTAssertEqual(track, original)
    }
}
