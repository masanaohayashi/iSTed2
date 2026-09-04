import Foundation
import STedCore
import STedPlayback

@main
@MainActor
enum STedPlay {
    static func main() async {
        do {
            let engine = PlaybackEngine()
            try await engine.prepareAudio()
            try engine.load(data: RCPDemo.middleC, title: "Demo C4")
            try await engine.play()
            try await Task.sleep(nanoseconds: 800_000_000)
            engine.stop()
            engine.audio.stopEngine()
            print("played demo C4 through \(engine.instrumentName)")
        } catch {
            FileHandle.standardError.write(Data("STedPlay failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
