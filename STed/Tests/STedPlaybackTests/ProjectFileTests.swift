import XCTest
import STedCore
@testable import STedPlayback

final class ProjectFileTests: XCTestCase {
    @MainActor
    func testNewProjectStartsWithoutFileAndSaveOverwritesKnownURL() throws {
        let engine = PlaybackEngine()
        try engine.loadDemo()
        XCTAssertFalse(engine.isDirty)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sted-project-\(UUID().uuidString).rcp")
        defer { try? FileManager.default.removeItem(at: url) }

        engine.newProject()
        XCTAssertNil(engine.currentFileURL)
        XCTAssertEqual(engine.song?.tracks.count, 1)
        XCTAssertTrue(engine.song?.tracks[0].events.first?.isTerminator == true)
        XCTAssertThrowsError(try engine.save()) { error in
            XCTAssertEqual(error as? ProjectFileError, .noCurrentFile)
        }

        try engine.save(to: url)
        XCTAssertEqual(engine.currentFileURL, url)
        XCTAssertFalse(engine.isDirty)

        engine.updateSongSettings(title: "Saved project", tempoBPM: 90, numerator: 3, denominator: 4)
        XCTAssertTrue(engine.isDirty)
        try engine.save()
        XCTAssertFalse(engine.isDirty)
        let loaded = try RCPDecoder.song(from: Data(contentsOf: url))
        XCTAssertEqual(loaded.title, "Saved project")
        XCTAssertEqual(loaded.tempoBPM, 90)
        XCTAssertEqual(loaded.beatNumerator, 3)
    }

    @MainActor
    func testLoadingAFileRemembersItsURLForSave() throws {
        let engine = PlaybackEngine()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sted-load-\(UUID().uuidString).rcp")
        defer { try? FileManager.default.removeItem(at: url) }
        try RCPDemo.phrase.write(to: url)

        try engine.load(url: url)
        XCTAssertEqual(engine.currentFileURL, url)
        XCTAssertFalse(engine.isDirty)
        engine.updateSongSettings(title: "Updated", tempoBPM: 100, numerator: 4, denominator: 4)
        XCTAssertTrue(engine.isDirty)
        try engine.save()
        XCTAssertFalse(engine.isDirty)
        XCTAssertEqual(try RCPDecoder.song(from: Data(contentsOf: url)).title, "Updated")
    }
}
