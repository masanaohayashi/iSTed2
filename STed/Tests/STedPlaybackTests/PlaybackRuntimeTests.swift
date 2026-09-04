import XCTest
@testable import STedPlayback
import STedCore

final class PlaybackRuntimeTests: XCTestCase {
    func testRenderAdvancesExactlyByAudioBufferDuration() {
        let runtime = PlaybackRuntime()
        runtime.load(events: [], songEnd: 10)
        runtime.play(from: 0)
        runtime.render(frameCount: 480, sampleRate: 48_000) { _, _ in }
        XCTAssertEqual(runtime.snapshot().position, 0.01, accuracy: 1e-12)
    }

    func testEventOffsetIsRelativeToTheAudioBuffer() {
        let runtime = PlaybackRuntime()
        runtime.load(
            events: [TimedMIDIEvent(seconds: 0.005, ticks: 1, bytes: [0x90, 60, 100])],
            songEnd: 1
        )
        runtime.play(from: 0)
        var offsets: [Int] = []
        var messages: [[UInt8]] = []
        runtime.render(frameCount: 480, sampleRate: 48_000) { bytes, offset in
            messages.append(bytes)
            offsets.append(Int(offset))
        }
        XCTAssertEqual(messages, [[0x90, 60, 100]])
        XCTAssertEqual(offsets, [240])
    }

    func testDoesNotEmitWhileStopped() {
        let runtime = PlaybackRuntime()
        runtime.load(
            events: [TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0x90, 60, 100])],
            songEnd: 1
        )
        var count = 0
        runtime.render(frameCount: 480, sampleRate: 48_000) { _, _ in count += 1 }
        XCTAssertEqual(count, 0)
        XCTAssertEqual(runtime.snapshot().position, 0)
    }
}
