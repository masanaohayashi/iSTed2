import XCTest
@testable import STedPlayback
import STedCore

final class PlaybackStartTests: XCTestCase {
    func testPlayButtonAlwaysJumpsToTheRequestedMeasure() {
        let song = Song(
            title: "",
            timeBase: 48,
            tempoBPM: 120,
            beatNumerator: 4,
            beatDenominator: 4,
            tracks: []
        )

        XCTAssertEqual(
            try XCTUnwrap(PlaybackStart.seconds(fromMeasure: 2, isPaused: false, song: song)),
            2.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(PlaybackStart.seconds(fromMeasure: 2, isPaused: true, song: song)),
            2.0,
            accuracy: 0.000_001
        )
        XCTAssertNil(PlaybackStart.seconds(fromMeasure: nil, isPaused: true, song: song))
        XCTAssertEqual(PlaybackStart.seconds(fromMeasure: nil, isPaused: false, song: song), 0)
    }
}

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

    func testPlayFromStartTimeEmitsTheEventAtThatTime() {
        let runtime = PlaybackRuntime()
        runtime.load(
            events: [
                TimedMIDIEvent(seconds: 0.0, ticks: 0, bytes: [0x90, 60, 100]),
                TimedMIDIEvent(seconds: 2.0, ticks: 192, bytes: [0x90, 64, 100])
            ],
            songEnd: 4
        )
        runtime.play(from: 2.0)
        var messages: [[UInt8]] = []
        runtime.render(frameCount: 48, sampleRate: 48_000) { bytes, _ in
            messages.append(bytes)
        }
        XCTAssertEqual(messages, [[0x90, 64, 100]])
    }

    func testPlayFromStartTimeRestoresTheLatestChannelStateBeforeTheNote() {
        let sequence = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 4,
            events: [
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xb0, 7, 80]),
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xe0, 0, 64]),
                TimedMIDIEvent(seconds: 1, ticks: 48, bytes: [0xb0, 7, 96]),
                TimedMIDIEvent(seconds: 1, ticks: 48, bytes: [0xe0, 32, 65]),
                TimedMIDIEvent(seconds: 2, ticks: 96, bytes: [0x90, 60, 100])
            ]
        )
        let runtime = PlaybackRuntime()
        runtime.load(sequence: sequence, songEnd: sequence.songEndSeconds)
        runtime.play(from: 2)

        var messages: [[UInt8]] = []
        runtime.render(frameCount: 48, sampleRate: 48_000) { bytes, _ in
            messages.append(bytes)
        }

        XCTAssertEqual(messages, [
            [0xb0, 7, 96],
            [0xe0, 32, 65],
            [0x90, 60, 100]
        ])
    }

    func testPlayFromStartTimeRestoresProgramAndAftertouchState() {
        let sequence = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 4,
            events: [
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xc0, 12]),
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xd0, 80]),
                TimedMIDIEvent(seconds: 1, ticks: 48, bytes: [0xa0, 60, 40]),
                TimedMIDIEvent(seconds: 2, ticks: 96, bytes: [0x90, 60, 100])
            ]
        )
        let runtime = PlaybackRuntime()
        runtime.load(sequence: sequence, songEnd: sequence.songEndSeconds)
        runtime.play(from: 2)

        var messages: [[UInt8]] = []
        runtime.render(frameCount: 48, sampleRate: 48_000) { bytes, _ in
            messages.append(bytes)
        }

        XCTAssertEqual(messages, [
            [0xc0, 12],
            [0xd0, 80],
            [0xa0, 60, 40],
            [0x90, 60, 100]
        ])
    }

    func testSeekDoesNotRestoreControllerValuesBeforeResetAllControllers() {
        let sequence = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 4,
            events: [
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xb0, 7, 80]),
                TimedMIDIEvent(seconds: 1, ticks: 48, bytes: [0xb0, 121, 0]),
                TimedMIDIEvent(seconds: 2, ticks: 96, bytes: [0x90, 60, 100])
            ]
        )
        let runtime = PlaybackRuntime()
        runtime.load(sequence: sequence, songEnd: sequence.songEndSeconds)
        runtime.play(from: 2)

        var messages: [[UInt8]] = []
        runtime.render(frameCount: 48, sampleRate: 48_000) { bytes, _ in
            messages.append(bytes)
        }

        XCTAssertEqual(messages, [[0x90, 60, 100]])
    }

    func testSeekReplaysOrderSensitiveControllersAndSysExBeforeTheNote() {
        let sequence = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 4,
            events: [
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xb0, 101, 0]),
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xb0, 100, 1]),
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xb0, 6, 12]),
                TimedMIDIEvent(seconds: 1, ticks: 48, bytes: [0xf0, 0x43, 0x10, 0xf7]),
                TimedMIDIEvent(seconds: 1, ticks: 48, bytes: [0xb0, 38, 34]),
                TimedMIDIEvent(seconds: 2, ticks: 96, bytes: [0x90, 60, 100])
            ]
        )
        let runtime = PlaybackRuntime()
        runtime.load(sequence: sequence, songEnd: sequence.songEndSeconds)
        runtime.play(from: 2)

        var messages: [[UInt8]] = []
        runtime.render(frameCount: 48, sampleRate: 48_000) { bytes, _ in
            messages.append(bytes)
        }

        XCTAssertEqual(messages, [
            [0xb0, 101, 0],
            [0xb0, 100, 1],
            [0xb0, 6, 12],
            [0xf0, 0x43, 0x10, 0xf7],
            [0xb0, 38, 34],
            [0x90, 60, 100]
        ])
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
