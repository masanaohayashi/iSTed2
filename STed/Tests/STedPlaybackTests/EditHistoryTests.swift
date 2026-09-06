import XCTest
import STedCore
@testable import STedPlayback

final class EditHistoryTests: XCTestCase {
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
}
