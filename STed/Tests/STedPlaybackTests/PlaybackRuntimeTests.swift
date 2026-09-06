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

    func testQueuedPlanSwitchesAtTheNextMeasureWithoutResettingPosition() {
        let first = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 8,
            events: [
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0x90, 60, 100]),
                TimedMIDIEvent(seconds: 1, ticks: 48, bytes: [0x80, 60, 0])
            ]
        )
        let second = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 8,
            events: [
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0xb0, 7, 99]),
                TimedMIDIEvent(seconds: 4, ticks: 192, bytes: [0xc0, 42]),
                TimedMIDIEvent(seconds: 4, ticks: 192, bytes: [0x90, 64, 100])
            ]
        )
        let runtime = PlaybackRuntime()
        runtime.load(plan: PlaybackPlan(revision: 1, sequence: first, songEndSeconds: 8))
        runtime.play(from: 0)

        runtime.render(frameCount: 48_000, sampleRate: 48_000) { _, _ in }
        XCTAssertEqual(runtime.snapshot().position, 1, accuracy: 1e-12)

        runtime.queue(plan: PlaybackPlan(revision: 2, sequence: second, songEndSeconds: 8))
        var messages: [[UInt8]] = []
        var offsets: [Int] = []
        runtime.render(frameCount: 144_000, sampleRate: 48_000) { bytes, offset in
            messages.append(bytes)
            offsets.append(Int(offset))
        }

        XCTAssertEqual(runtime.snapshot().position, 4, accuracy: 1e-12)
        XCTAssertEqual(runtime.snapshot().planRevision, 2)
        XCTAssertEqual(offsets.last, 144_000)
        XCTAssertEqual(messages.suffix(3), [
            [0xb0, 7, 99],
            [0xc0, 42],
            [0x90, 64, 100]
        ])
        XCTAssertEqual(offsets.suffix(3), [144_000, 144_000, 144_000])
        XCTAssertEqual(messages.filter { $0.count == 3 && $0[0] & 0xf0 == 0xb0 && $0[1] == 123 }.count, 16)
        XCTAssertEqual(messages.filter { $0.count == 3 && $0[0] & 0xf0 == 0xb0 && $0[1] == 64 }.count, 16)
    }

    func testQueuedPlanKeepsWallClockTimeWhenTempoChanges() {
        let first = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 8,
            events: [TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0x90, 60, 100])]
        )
        let second = RCPSequence(
            timeBase: 48,
            tempoBPM: 120,
            songEndSeconds: 4,
            events: [TimedMIDIEvent(seconds: 2, ticks: 192, bytes: [0x90, 64, 100])]
        )
        let runtime = PlaybackRuntime()
        runtime.load(plan: PlaybackPlan(revision: 1, sequence: first, songEndSeconds: 8))
        runtime.play(from: 0)
        runtime.render(frameCount: 48_000, sampleRate: 48_000) { _, _ in }

        runtime.queue(plan: PlaybackPlan(revision: 2, sequence: second, songEndSeconds: 4))
        var offsets: [Int] = []
        var messages: [[UInt8]] = []
        runtime.render(frameCount: 144_000, sampleRate: 48_000) { bytes, offset in
            messages.append(bytes)
            offsets.append(Int(offset))
        }

        XCTAssertEqual(runtime.snapshot().planRevision, 2)
        XCTAssertEqual(runtime.snapshot().timelineOffset, 2, accuracy: 1e-12)
        XCTAssertEqual(offsets.last, 144_000)
        XCTAssertEqual(messages.last, [0x90, 64, 100])
    }

    func testLatestQueuedPlanReplacesAnEarlierPendingPlanAtTheSameBoundary() {
        let first = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 8,
            events: [TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0x90, 60, 100])]
        )
        let second = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 8,
            events: [TimedMIDIEvent(seconds: 4, ticks: 192, bytes: [0xc0, 41])]
        )
        let third = RCPSequence(
            timeBase: 48,
            tempoBPM: 60,
            songEndSeconds: 8,
            events: [TimedMIDIEvent(seconds: 4, ticks: 192, bytes: [0xc0, 42])]
        )
        let runtime = PlaybackRuntime()
        runtime.load(plan: PlaybackPlan(revision: 1, sequence: first, songEndSeconds: 8))
        runtime.play(from: 0)
        runtime.render(frameCount: 48_000, sampleRate: 48_000) { _, _ in }

        runtime.queue(plan: PlaybackPlan(revision: 2, sequence: second, songEndSeconds: 8))
        runtime.queue(plan: PlaybackPlan(revision: 3, sequence: third, songEndSeconds: 8))
        var messages: [[UInt8]] = []
        runtime.render(frameCount: 144_000, sampleRate: 48_000) { bytes, _ in
            messages.append(bytes)
        }

        XCTAssertEqual(runtime.snapshot().planRevision, 3)
        XCTAssertFalse(messages.contains([0xc0, 41]))
        XCTAssertEqual(messages.last, [0xc0, 42])
    }
}
