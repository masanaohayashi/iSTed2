import XCTest
import STedCore
@testable import STedPlayback

final class EditHistoryTests: XCTestCase {
    @MainActor
    func testSameMeasureCreationAndSourceDeletionAreUndoable() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let id = try XCTUnwrap(engine.song?.tracks.first?.id)
        let end = try XCTUnwrap(engine.song?.tracks.first?.terminatorIndex)
        engine.insertEvent(trackID: id, at: end, .measureLine)
        let before = engine.song
        XCTAssertTrue(engine.insertSameMeasure(trackID: id, at: end + 1, referringTo: 1))
        let referenced = engine.song
        engine.undo()
        XCTAssertEqual(engine.song, before)
        engine.redo()
        XCTAssertEqual(engine.song, referenced)
        engine.replaceEvents(trackID: id, in: 0..<(end + 1), with: [])
        XCTAssertFalse(engine.song!.tracks[0].events.contains { $0.command == 0xfc })
        engine.undo()
        XCTAssertEqual(engine.song, referenced)
    }

    @MainActor
    func testRangeReplacementIsOneUndoStep() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let before = try XCTUnwrap(engine.song)
        let id = before.tracks[0].id
        engine.replaceEvents(trackID: id, in: 0..<2, with: [.measureLine])
        let after = engine.song
        engine.undo()
        XCTAssertEqual(engine.song, before)
        XCTAssertFalse(engine.canUndo)
        engine.redo()
        XCTAssertEqual(engine.song, after)
    }

    @MainActor
    func testEditsUndoRedoAndBranch() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let before = try XCTUnwrap(engine.song)
        let id = before.tracks[0].id
        engine.updateEvent(trackID: id, index: 0, TrackEvent(command: 72, delay: 48, param1: 30, param2: 90))
        let edited = engine.song
        engine.deleteEvent(trackID: id, at: 1)
        let deleted = engine.song
        engine.undo()
        XCTAssertEqual(engine.song, edited)
        engine.undo()
        XCTAssertEqual(engine.song, before)
        XCTAssertFalse(engine.canUndo)
        engine.redo()
        XCTAssertEqual(engine.song, edited)
        engine.redo()
        XCTAssertEqual(engine.song, deleted)
        engine.undo()
        engine.setMuted(true, trackID: id)
        XCTAssertFalse(engine.canRedo)
        engine.undo()
        XCTAssertEqual(engine.song, edited)
    }

    @MainActor
    func testProgramInsertIsOneUndoAndRoundTripsRCP() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let before = try engine.encodedRCP()
        let id = try XCTUnwrap(engine.song?.tracks.first?.id)
        engine.beginEdit()
        engine.insertEvent(trackID: id, at: 0, .specialControllerPlaceholder)
        engine.updateEvent(trackID: id, index: 0, TrackEvent(command: 0xec, delay: 0, param1: 42, param2: 0))
        engine.endEdit()
        let after = try engine.encodedRCP()
        engine.undo()
        XCTAssertEqual(try engine.encodedRCP(), before)
        XCTAssertFalse(engine.canUndo)
        engine.redo()
        XCTAssertEqual(try engine.encodedRCP(), after)
    }

    @MainActor
    func testCancelledAndNoOpEditsDoNotPolluteHistory() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let id = try XCTUnwrap(engine.song?.tracks.first?.id)
        let event = try XCTUnwrap(engine.song?.tracks.first?.events.first)
        engine.updateEvent(trackID: id, index: 0, event)
        XCTAssertFalse(engine.canUndo)
        engine.beginEdit()
        engine.insertEvent(trackID: id, at: 0)
        engine.deleteEvent(trackID: id, at: 0)
        engine.endEdit()
        XCTAssertFalse(engine.canUndo)
        engine.insertEvent(trackID: id, at: 0)
        engine.undo()
        engine.beginEdit()
        engine.insertEvent(trackID: id, at: 0)
        engine.deleteEvent(trackID: id, at: 0)
        engine.endEdit()
        XCTAssertTrue(engine.canRedo)
        try engine.loadDemo()
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.canRedo)
    }

    @MainActor
    func testUndoAnOpenInsertionAndTrackSettings() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let before = try XCTUnwrap(engine.song)
        let id = before.tracks[0].id
        engine.beginEdit()
        engine.insertEvent(trackID: id, at: 0)
        engine.undo()
        XCTAssertEqual(engine.song, before)
        engine.redo()
        XCTAssertEqual(engine.song?.tracks[0].events.count, before.tracks[0].events.count + 1)
        engine.updateTrack(trackID: id, midiChannel: 3, startTick: 4, keyShift: 2, memo: "edited")
        engine.undo()
        XCTAssertEqual(engine.song?.tracks[0].memo, before.tracks[0].memo)
    }
    @MainActor
    func testInlineSameMeasureIsOneUndoAndCancelPreservesRedo() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let before = try XCTUnwrap(engine.song)
        let track = before.tracks[0]
        engine.beginEdit()
        XCTAssertTrue(engine.insertSameMeasure(trackID: track.id, at: track.terminatorIndex, referringTo: 1))
        let row = try XCTUnwrap(engine.song?.tracks[0].events.firstIndex { $0.command == 0xfc })
        XCTAssertFalse(engine.insertSameMeasure(trackID: track.id, at: row, referringTo: 1024))
        XCTAssertTrue(engine.insertSameMeasure(trackID: track.id, at: row, referringTo: 1))
        engine.endEdit()
        let after = engine.song
        engine.undo()
        XCTAssertEqual(engine.song, before)
        XCTAssertFalse(engine.canUndo)
        engine.beginEdit()
        XCTAssertTrue(engine.insertSameMeasure(trackID: track.id, at: track.terminatorIndex, referringTo: 1))
        engine.cancelEdit()
        XCTAssertEqual(engine.song, before)
        XCTAssertFalse(engine.canUndo)
        XCTAssertTrue(engine.canRedo)
        engine.redo()
        XCTAssertEqual(engine.song, after)
    }

}
