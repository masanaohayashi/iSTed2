import SwiftUI
import STedPlayback

@main
struct STedApplication: App {
    @StateObject private var engine = PlaybackEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .task {
                    do {
                        try await engine.prepareAudio()
                    } catch {
                        engine.reportAudioError(error)
                    }
                    if ProcessInfo.processInfo.arguments.contains("--demo") {
                        do {
                            try engine.loadDemo()
                        } catch {
                            engine.reportError(error)
                        }
                    }
                }
        }
    }
}
