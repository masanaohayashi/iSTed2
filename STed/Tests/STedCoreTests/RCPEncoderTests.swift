import XCTest
@testable import STedCore

final class RCPEncoderTests: XCTestCase {
    func testDemoPhraseRoundTripsTheWholeSong() throws {
        try assertRoundTrip(RCPDemo.phrase)
    }

    func testDemoMiddleCRoundTripsTheWholeSong() throws {
        try assertRoundTrip(RCPDemo.middleC)
    }

    func testRoundTripsMutedTrackControllersAndChords() throws {
        try assertRoundTrip(
            makeRCP(
                title: "Round Trip",
                tracks: [
                    TestTrack(number: 1, channel: 0, mode: 0, memo: "melody", events: [
                        [60, 0, 36, 100],
                        [64, 0, 36, 100],
                        [67, 48, 36, 100],
                        [0xeb, 0, 7, 100],
                        [0xec, 0, 12, 0],
                        [0xee, 0, 0x00, 0x40],
                        [0xfe, 0, 0, 0]
                    ]),
                    TestTrack(number: 2, channel: 1, mode: 1, memo: "muted", events: [
                        [48, 24, 12, 80],
                        [0xfe, 0, 0, 0]
                    ])
                ]
            )
        )
    }

    func testRoundTripsEditedTrackAttributesAndGateTime() throws {
        var song = try RCPDecoder.song(from: RCPDemo.phrase)
        song.tempoBPM = 96
        song.tracks[0].keyShift = -2
        song.tracks[0].startTick = 12
        song.tracks[0].events[0].param1 = 12
        song.tracks[1].mode = .mute
        song.tracks[1].midiChannel = nil

        let loaded = try RCPDecoder.song(from: RCPEncoder.encode(song))
        XCTAssertEqual(loaded, song)
        XCTAssertEqual(try loaded.playbackSequence(), try song.playbackSequence())
    }
}

private func assertRoundTrip(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
    let original = try RCPDecoder.song(from: data)
    let loaded = try RCPDecoder.song(from: RCPEncoder.encode(original))
    XCTAssertEqual(loaded, original, file: file, line: line)
    XCTAssertEqual(
        try loaded.playbackSequence(),
        try original.playbackSequence(),
        file: file,
        line: line
    )
}
