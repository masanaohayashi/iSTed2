import Foundation
import XCTest
@testable import STedCore

final class RCPDecoderTests: XCTestCase {
    func testDecodesSingleNoteIntoTimedMIDIEvents() throws {
        let data = makeRCP(
            trackEvents: [
                [60, 48, 36, 100],
                [0xfe, 0, 0, 0]
            ]
        )

        let sequence = try RCPDecoder.decode(data)

        XCTAssertEqual(sequence.timeBase, 48)
        XCTAssertEqual(sequence.tempoBPM, 120)
        XCTAssertEqual(sequence.events.map(\.bytes), [
            [0x90, 60, 100],
            [0x80, 60, 0]
        ])
        XCTAssertEqual(sequence.events.map(\.ticks), [0, 36])
        XCTAssertEqual(sequence.events[0].seconds, 0.0, accuracy: 0.000_001)
        XCTAssertEqual(sequence.events[1].seconds, 0.375, accuracy: 0.000_001)
    }

    func testDecodesChordKeepingSameTickOrder() throws {
        let data = makeRCP(
            trackEvents: [
                [60, 0, 36, 100],
                [64, 0, 36, 100],
                [67, 48, 36, 100],
                [0xfe, 0, 0, 0]
            ]
        )

        let sequence = try RCPDecoder.decode(data)

        XCTAssertEqual(sequence.events.map(\.bytes), [
            [0x90, 60, 100],
            [0x90, 64, 100],
            [0x90, 67, 100],
            [0x80, 60, 0],
            [0x80, 64, 0],
            [0x80, 67, 0]
        ])
        XCTAssertEqual(sequence.events.map(\.ticks), [0, 0, 0, 36, 36, 36])
    }

    func testZeroGateOrVelocityDoesNotEmitANote() throws {
        let data = makeRCP(
            trackEvents: [
                [60, 48, 0, 100],
                [64, 48, 36, 0],
                [67, 48, 36, 100],
                [0xfe, 0, 0, 0]
            ]
        )

        let sequence = try RCPDecoder.decode(data)

        XCTAssertEqual(sequence.events.map(\.bytes), [
            [0x90, 67, 100],
            [0x80, 67, 0]
        ])
    }

    func testGateLongerThanStepKeepsTheNoteOnUntilTheGatePosition() throws {
        let data = makeRCP(
            trackEvents: [
                [60, 12, 23, 100],
                [64, 12, 8, 100],
                [0xfe, 0, 0, 0]
            ]
        )

        let sequence = try RCPDecoder.decode(data)

        XCTAssertEqual(sequence.events.map(\.bytes), [
            [0x90, 60, 100],
            [0x90, 64, 100],
            [0x80, 64, 0],
            [0x80, 60, 0]
        ])
        XCTAssertEqual(sequence.events.map(\.ticks), [0, 12, 20, 23])
    }

    func testDecodesControlChangeProgramChangeAndPitchBend() throws {
        let data = makeRCP(
            trackEvents: [
                [0xeb, 0, 7, 100],
                [0xec, 0, 12, 0],
                [0xee, 0, 0x00, 0x40],
                [0xfe, 0, 0, 0]
            ]
        )

        let sequence = try RCPDecoder.decode(data)

        XCTAssertEqual(sequence.events.map(\.bytes), [
            [0xb0, 7, 100],
            [0xc0, 12],
            [0xe0, 0x00, 0x40]
        ])
    }

    func testRejectsNonRCPData() {
        XCTAssertThrowsError(try RCPDecoder.decode(Data([0, 1, 2, 3]))) { error in
            XCTAssertEqual(error as? RCPError, .notRCPV2)
        }
    }
}

private func makeRCP(trackEvents: [[UInt8]]) -> Data {
    let headerSize = 0x586
    let trackHeaderSize = 0x2c
    let trackLength = trackHeaderSize + trackEvents.count * 4
    var data = Data(repeating: 0, count: headerSize + trackLength)

    let signature = Array("RCM-PC98V2.0(C)COME ON MUSIC".utf8)
    data.replaceSubrange(0..<signature.count, with: signature)
    writeUInt16LE(48, at: 0x1c0, in: &data)
    data[0x1c1] = 120
    data[0x1c2] = 4
    data[0x1c3] = 4
    data[0x1e6] = 1

    let trackOffset = headerSize
    writeUInt16LE(UInt16(trackLength), at: trackOffset, in: &data)
    data[trackOffset + 4] = 0
    data[trackOffset + 5] = 0
    data[trackOffset + 6] = 0
    data[trackOffset + 7] = 0

    for (index, event) in trackEvents.enumerated() {
        let offset = trackOffset + trackHeaderSize + index * 4
        data.replaceSubrange(offset..<(offset + 4), with: event)
    }

    return data
}

private func writeUInt16LE(_ value: UInt16, at offset: Int, in data: inout Data) {
    data[offset] = UInt8(value & 0xff)
    data[offset + 1] = UInt8(value >> 8)
}
