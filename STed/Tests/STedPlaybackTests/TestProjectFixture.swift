import Foundation
import STedCore
@testable import STedPlayback

enum TestProjectFixture {
    @MainActor
    static func loadPhrase(into engine: PlaybackEngine) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sted-test-project-\(UUID().uuidString).rcp")
        defer { try? FileManager.default.removeItem(at: url) }

        try RCPDemo.phrase.write(to: url, options: .atomic)
        try engine.load(url: url)
    }
}
