import Foundation
import XCTest
@testable import STedCore

final class SongTests: XCTestCase {
    func testLoadsTrackListAndTitleFromRCP() throws {
        let data = makeRCP(
            title: "Test Song",
            tracks: [
                TestTrack(number: 1, channel: 0, mode: 0, memo: "melody", events: [
                    [60, 48, 36, 100],
                    [0xfe, 0, 0, 0]
                ]),
                TestTrack(number: 2, channel: 1, mode: 1, memo: "muted", events: [
                    [64, 48, 36, 100],
                    [0xfe, 0, 0, 0]
                ])
            ]
        )

        let song = try RCPDecoder.song(from: data)

        XCTAssertEqual(song.title, "Test Song")
        XCTAssertEqual(song.tempoBPM, 120)
        XCTAssertEqual(song.timeBase, 48)
        XCTAssertEqual(song.tracks.count, 2)
        XCTAssertEqual(song.tracks[0].number, 1)
        XCTAssertEqual(song.tracks[0].midiChannel, 1)
        XCTAssertEqual(song.tracks[0].mode, .play)
        XCTAssertEqual(song.tracks[0].memo, "melody")
        XCTAssertEqual(song.tracks[1].mode, .mute)
        XCTAssertEqual(song.tracks[1].midiChannel, 2)
    }

    func testMutedTracksAreOmittedFromPlayback() throws {
        let data = makeRCP(
            tracks: [
                TestTrack(number: 1, channel: 0, mode: 0, events: [
                    [60, 48, 36, 100],
                    [0xfe, 0, 0, 0]
                ]),
                TestTrack(number: 2, channel: 1, mode: 1, events: [
                    [64, 48, 36, 100],
                    [0xfe, 0, 0, 0]
                ])
            ]
        )

        var song = try RCPDecoder.song(from: data)
        var playback = try song.playbackSequence()
        XCTAssertEqual(playback.events.map(\.bytes), [
            [0x90, 60, 100],
            [0x80, 60, 0]
        ])

        song.tracks[0].mode = .mute
        song.tracks[1].mode = .play
        playback = try song.playbackSequence()
        XCTAssertEqual(playback.events.map(\.bytes), [
            [0x91, 64, 100],
            [0x81, 64, 0]
        ])
    }

    func testEventRowsUseMeasureAndStep() throws {
        let data = makeRCP(
            tracks: [
                TestTrack(number: 1, channel: 0, events: [
                    [60, 192, 36, 100],
                    [64, 48, 36, 90],
                    [0xfe, 0, 0, 0]
                ])
            ]
        )

        let song = try RCPDecoder.song(from: data)
        let rows = song.tracks[0].eventRows(
            timeBase: song.timeBase,
            beatNumerator: song.beatNumerator,
            beatDenominator: song.beatDenominator
        )

        XCTAssertEqual(rows[0].time.measure, 1)
        XCTAssertEqual(rows[0].time.step, 0)
        XCTAssertEqual(rows[0].label, "C4")
        XCTAssertEqual(rows[0].st, 192)
        XCTAssertEqual(rows[0].gt, 36)
        XCTAssertEqual(rows[0].vel, 100)

        XCTAssertEqual(rows[1].time.measure, 2)
        XCTAssertEqual(rows[1].time.step, 0)
        XCTAssertEqual(rows[1].label, "E4")
        XCTAssertEqual(rows[1].st, 48)
        XCTAssertEqual(rows[1].vel, 90)
    }

    func testMusicalTimeSplitsTicksIntoMeasures() {
        let time = MusicalTime(
            tick: 192,
            timeBase: 48,
            beatNumerator: 4,
            beatDenominator: 4
        )
        XCTAssertEqual(time.measure, 2)
        XCTAssertEqual(time.step, 0)
    }

    func testMeasureStartTickAndSecondsMatchTheFirstStep() {
        let song = Song(
            title: "",
            timeBase: 48,
            tempoBPM: 120,
            beatNumerator: 4,
            beatDenominator: 4,
            tracks: []
        )

        XCTAssertEqual(song.startTick(ofMeasure: 1), 0)
        XCTAssertEqual(song.startTick(ofMeasure: 2), 192)
        XCTAssertEqual(song.seconds(atTick: 0), 0, accuracy: 0.000_001)
        XCTAssertEqual(song.seconds(atTick: 192), 2.0, accuracy: 0.000_001)
    }
}

struct TestTrack {
    var number: UInt8 = 1
    var channel: UInt8 = 0
    var mode: UInt8 = 0
    var memo: String = ""
    var events: [[UInt8]]
}

func makeRCP(title: String = "", tracks: [TestTrack]) -> Data {
    let headerSize = 0x586
    let trackHeaderSize = 0x2c
    var data = Data(repeating: 0, count: headerSize)
    let signature = Array("RCM-PC98V2.0(C)COME ON MUSIC".utf8)
    data.replaceSubrange(0..<signature.count, with: signature)

    let titleBytes = Array(title.utf8.prefix(64))
    data.replaceSubrange(0x20..<(0x20 + titleBytes.count), with: titleBytes)

    data[0x1c0] = 48
    data[0x1c1] = 120
    data[0x1c2] = 4
    data[0x1c3] = 4
    data[0x1e6] = UInt8(tracks.count)

    for track in tracks {
        let trackLength = trackHeaderSize + track.events.count * 4
        var chunk = Data(repeating: 0, count: trackLength)
        chunk[0] = UInt8(trackLength & 0xff)
        chunk[1] = UInt8(trackLength >> 8)
        chunk[2] = track.number
        chunk[4] = track.channel
        chunk[7] = track.mode
        let memoBytes = Array(track.memo.utf8.prefix(36))
        chunk.replaceSubrange(8..<(8 + memoBytes.count), with: memoBytes)
        for (index, event) in track.events.enumerated() {
            let offset = trackHeaderSize + index * 4
            chunk.replaceSubrange(offset..<(offset + 4), with: event)
        }
        data.append(chunk)
    }
    return data
}
