import AudioToolbox
import STedCore
import STedPlayback
import XCTest

final class EventSchedulerTests: XCTestCase {
    func testAdvancesInTimeOrderWithoutReorderingSameTickEvents() {
        let scheduler = EventScheduler(
            events: [
                TimedMIDIEvent(seconds: 0.0, ticks: 0, bytes: [0x90, 60, 100]),
                TimedMIDIEvent(seconds: 0.0, ticks: 0, bytes: [0xb0, 7, 100]),
                TimedMIDIEvent(seconds: 0.375, ticks: 36, bytes: [0x80, 60, 0])
            ]
        )
        var messages: [[UInt8]] = []

        scheduler.advance(to: 0.0, send: { messages.append($0) })
        XCTAssertEqual(messages, [
            [0x90, 60, 100],
            [0xb0, 7, 100]
        ])

        scheduler.advance(to: 0.374, send: { messages.append($0) })
        XCTAssertEqual(messages.count, 2)

        scheduler.advance(to: 0.375, send: { messages.append($0) })
        XCTAssertEqual(messages, [
            [0x90, 60, 100],
            [0xb0, 7, 100],
            [0x80, 60, 0]
        ])
    }

    func testResetRewindsWithoutSending() {
        let scheduler = EventScheduler(
            events: [
                TimedMIDIEvent(seconds: 0.0, ticks: 0, bytes: [0x90, 60, 100]),
                TimedMIDIEvent(seconds: 1.0, ticks: 96, bytes: [0x80, 60, 0])
            ]
        )
        var messages: [[UInt8]] = []
        scheduler.advance(to: 0.0, send: { messages.append($0) })
        scheduler.reset()
        scheduler.advance(to: 0.0, send: { messages.append($0) })
        XCTAssertEqual(messages, [
            [0x90, 60, 100],
            [0x90, 60, 100]
        ])
    }

    func testJumpSkipsAlreadyElapsedEventsWithoutSending() {
        let scheduler = EventScheduler(
            events: [
                TimedMIDIEvent(seconds: 0.0, ticks: 0, bytes: [0x90, 60, 100]),
                TimedMIDIEvent(seconds: 0.375, ticks: 36, bytes: [0x80, 60, 0]),
                TimedMIDIEvent(seconds: 1.0, ticks: 96, bytes: [0x90, 64, 100])
            ]
        )
        var messages: [[UInt8]] = []
        scheduler.jump(to: 0.5)
        scheduler.advance(to: 1.0, send: { messages.append($0) })
        XCTAssertEqual(messages, [
            [0x90, 64, 100]
        ])
    }

    func testJumpIncludesEventsAtTheStartTime() {
        let scheduler = EventScheduler(
            events: [
                TimedMIDIEvent(seconds: 0.0, ticks: 0, bytes: [0x90, 60, 100]),
                TimedMIDIEvent(seconds: 2.0, ticks: 192, bytes: [0x90, 64, 100]),
                TimedMIDIEvent(seconds: 2.5, ticks: 240, bytes: [0x90, 67, 100])
            ]
        )
        var fromStart: [[UInt8]] = []
        scheduler.jump(to: 0)
        scheduler.advance(to: 0, send: { fromStart.append($0) })
        XCTAssertEqual(fromStart, [[0x90, 60, 100]])

        var fromMeasure: [[UInt8]] = []
        scheduler.jump(to: 2.0)
        scheduler.advance(to: 2.0, send: { fromMeasure.append($0) })
        XCTAssertEqual(fromMeasure, [[0x90, 64, 100]])
    }

    func testSampleOffsetsAreRelativeToBufferStart() {
        let scheduler = EventScheduler(
            events: [
                TimedMIDIEvent(seconds: 0.010, ticks: 1, bytes: [0xc0, 12])
            ]
        )
        var offsets: [AUEventSampleTime] = []
        scheduler.advance(to: 0.020, bufferStart: 0.0, sampleRate: 1000) { _, offset in
            offsets.append(offset)
        }
        XCTAssertEqual(offsets, [10])
    }

    func testPacedPrefixKeepsMusicalEventsBehindStateRestore() {
        let scheduler = EventScheduler(
            events: [
                TimedMIDIEvent(seconds: 0, ticks: 0, bytes: [0x90, 60, 100])
            ]
        )
        let prefix: [[UInt8]] = [
            [0xb0, 7, 80],
            [0xc0, 12]
        ]
        var messages: [[UInt8]] = []
        var offsets: [Int] = []

        scheduler.jump(
            to: 0,
            prefix: prefix,
            timelineOffset: 0,
            prefixIntervalSeconds: 0.01,
            prefixTailSeconds: 0.02
        )
        scheduler.advance(to: 0.005, bufferStart: 0, sampleRate: 1_000) { bytes, offset in
            messages.append(bytes)
            offsets.append(Int(offset))
        }
        XCTAssertEqual(messages, [prefix[0]])
        XCTAssertEqual(offsets, [0])

        scheduler.advance(to: 0.015, bufferStart: 0, sampleRate: 1_000) { bytes, offset in
            messages.append(bytes)
            offsets.append(Int(offset))
        }
        XCTAssertEqual(messages, [prefix[0], prefix[1]])
        XCTAssertEqual(offsets, [0, 10])

        scheduler.advance(to: 0.05, bufferStart: 0, sampleRate: 1_000) { bytes, offset in
            messages.append(bytes)
            offsets.append(Int(offset))
        }
        XCTAssertEqual(messages, [
            prefix[0],
            prefix[1],
            [0x90, 60, 100]
        ])
        XCTAssertEqual(offsets, [0, 10, 40])
    }
}
