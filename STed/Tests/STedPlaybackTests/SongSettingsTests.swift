import XCTest
import STedCore
@testable import STedPlayback

final class SongSettingsTests: XCTestCase {
    @MainActor
    func testSongSettingsPersistAndUndoTogether() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let original = try XCTUnwrap(engine.song)
        engine.updateSongSettings(title: "My song", tempoBPM: 90, numerator: 3, denominator: 4)
        let loaded = try RCPDecoder.song(from: engine.encodedRCP())
        XCTAssertEqual(loaded.title, "My song")
        XCTAssertEqual(loaded.tempoBPM, 90)
        XCTAssertEqual(loaded.beatNumerator, 3)
        engine.undo()
        XCTAssertEqual(engine.song, original)
        XCTAssertEqual(engine.title, original.title)
        engine.redo()
        XCTAssertEqual(engine.song?.tempoBPM, 90)
        XCTAssertEqual(engine.title, "My song")
    }

    @MainActor
    func testAddConfigureDuplicateDeleteAndUndoTracks() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        let id = try XCTUnwrap(engine.addTrack())
        XCTAssertEqual(engine.selectedTrackID, id)
        XCTAssertEqual(engine.selectedTrack?.events.count, 1)
        XCTAssertTrue(engine.selectedTrack?.events.first?.isTerminator == true)
        engine.updateTrack(trackID: id, midiChannel: 7, startTick: 10, keyShift: -2, memo: "Strings")
        let loaded = try RCPDecoder.song(from: engine.encodedRCP())
        XCTAssertEqual(loaded.tracks.last?.memo, "Strings")
        XCTAssertEqual(loaded.tracks.last?.midiChannel, 7)
        XCTAssertEqual(loaded.tracks.last?.startTick, 10)
        XCTAssertEqual(loaded.tracks.last?.keyShift, -2)
        let copyID = try XCTUnwrap(engine.addTrack(copying: id))
        XCTAssertNotEqual(copyID, id)
        XCTAssertEqual(engine.selectedTrack?.midiChannel, 7)
        engine.deleteTrack(id: copyID)
        XCTAssertEqual(engine.song?.tracks.count, 3)
        engine.undo()
        XCTAssertEqual(engine.song?.tracks.count, 4)
        engine.undo()
        XCTAssertEqual(engine.song?.tracks.count, 3)
        XCTAssertTrue(engine.song!.tracks.contains { $0.id == engine.selectedTrackID })
    }

    @MainActor
    func testRCPTrackLimitAndLastTrackProtection() async throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        for _ in 0..<40 { _ = engine.addTrack() }
        XCTAssertEqual(engine.song?.tracks.count, 36)
        XCTAssertFalse(engine.canAddTrack)
        XCTAssertEqual(Set(engine.song!.tracks.map(\.number)).count, 36)
        for track in engine.song!.tracks { engine.deleteTrack(id: track.id) }
        XCTAssertEqual(engine.song?.tracks.count, 1)
        XCTAssertEqual(try RCPDecoder.song(from: engine.encodedRCP()).tracks.count, 1)
    }
}
