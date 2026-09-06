import XCTest
import STedCore
@testable import STedPlayback

final class PlaybackPositionTests: XCTestCase {
    func testLaterMeasureSeekUsesTheSameTempoAsScheduledNotes() throws {
        var events = [TrackEvent(command: 0xe7, delay: 0, param1: 128, param2: 0)]
        for _ in 0..<16 {
            events.append(TrackEvent(command: 60, delay: 192, param1: 24, param2: 100))
            events.append(.measureLine)
        }
        events.append(TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0))
        let song = Song(title: "tempo seek", timeBase: 48, tempoBPM: 120,
                        beatNumerator: 4, beatDenominator: 4,
                        tracks: [Track(id: 0, number: 1, midiChannel: 1, events: events)])
        let sequence = try song.playbackSequence()
        let note = try XCTUnwrap(sequence.events.first { $0.ticks == 192 * 12 && $0.bytes.first == 0x90 })
        let start = try XCTUnwrap(PlaybackStart.seconds(fromMeasure: 13, isPaused: false, song: song, sequence: sequence))
        XCTAssertEqual(start, note.seconds, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(PlaybackStart.seconds(fromMeasure: 13, isPaused: false, song: song)), start, accuracy: 0.000001)
        XCTAssertEqual(sequence.tick(atSeconds: start), 192 * 12)
        let runtime = PlaybackRuntime()
        runtime.load(events: sequence.events, songEnd: sequence.songEndSeconds + sequence.lastBarSeconds)
        runtime.play(from: start)
        var sent: [[UInt8]] = []
        runtime.render(frameCount: 480, sampleRate: 48000) { bytes, _ in sent.append(bytes) }
        XCTAssertTrue(sent.contains { $0.first == 0x90 })
        XCTAssertFalse(runtime.snapshot().finished)
    }
    func testTempoChangesAndGradualRampsRoundTripEveryScheduledEvent() throws {
        var events: [TrackEvent] = []
        for measure in 0..<40 {
            if measure == 4 || measure == 16 || measure == 24 {
                events.append(TrackEvent(command: 0xe7, delay: 0,
                                         param1: measure == 16 ? 32 : 96,
                                         param2: measure == 24 ? 8 : 0))
            }
            events.append(TrackEvent(command: 60, delay: 192, param1: 24, param2: 100))
            events.append(.measureLine)
        }
        events.append(TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0))
        let song = Song(title: "ramps", timeBase: 48, tempoBPM: 123,
                        beatNumerator: 4, beatDenominator: 4,
                        tracks: [Track(id: 0, number: 1, midiChannel: 1, events: events)])
        let sequence = try song.playbackSequence()
        for event in sequence.events {
            XCTAssertEqual(sequence.seconds(atTick: event.ticks), event.seconds, accuracy: 1e-8)
            XCTAssertEqual(sequence.tick(atSeconds: event.seconds), event.ticks)
        }
        for tick in stride(from: 0, to: 40 * 192, by: 13) {
            XCTAssertEqual(sequence.tick(atSeconds: sequence.seconds(atTick: tick)), tick)
        }
    }

}
