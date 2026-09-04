import Foundation

public enum RCPEncoder {
    public static func encode(_ song: Song) -> Data {
        var data = Data(repeating: 0, count: rcpHeaderSize)
        let signature = Array(rcpHeaderPrefix.utf8)
        data.replaceSubrange(0..<signature.count, with: signature)
        writePackedString(song.title, at: 0x20, length: 64, in: &data)
        data[0x1c0] = UInt8(song.timeBase & 0xff)
        data[0x1e7] = UInt8((song.timeBase >> 8) & 0xff)
        data[0x1c1] = UInt8(min(255, max(1, song.tempoBPM)))
        data[0x1c2] = UInt8(min(255, max(1, song.beatNumerator)))
        data[0x1c3] = UInt8(song.beatDenominator)
        data[0x1e6] = UInt8(min(36, song.tracks.count))

        let sysEx = song.userSysEx
        for index in 0..<8 {
            let offset = 0x406 + index * 0x30 + 0x18
            var bytes = [UInt8](repeating: 0, count: 0x18)
            if index < sysEx.count {
                let source = sysEx[index].prefix(0x18)
                bytes.replaceSubrange(0..<source.count, with: source)
            }
            data.replaceSubrange(offset..<(offset + 0x18), with: bytes)
        }

        for track in song.tracks.prefix(36) {
            data.append(encodeTrack(track))
        }
        return data
    }
}

private let rcpHeaderPrefix = "RCM-PC98V2.0(C)COME ON MUSIC"
private let rcpHeaderSize = 0x586
private let rcpTrackHeaderSize = 0x2c

private func encodeTrack(_ track: Track) -> Data {
    var events = track.events
    if events.last?.command != 0xfe && events.last?.command != 0xff {
        events.append(TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0))
    }
    let trackLength = rcpTrackHeaderSize + events.count * 4
    var chunk = Data(repeating: 0, count: trackLength)
    chunk[0] = UInt8(trackLength & 0xff)
    chunk[1] = UInt8((trackLength >> 8) & 0xff)
    chunk[2] = UInt8(min(255, max(0, track.number)))
    chunk[3] = track.rhythm
    if let channel = track.midiChannel, (1...16).contains(channel) {
        chunk[4] = UInt8(channel - 1)
    } else {
        chunk[4] = 0xff
    }
    chunk[5] = encodeSignedSevenBit(track.keyShift)
    chunk[6] = UInt8(bitPattern: Int8(clamping: track.startTick))
    chunk[7] = track.mode.rcpByte
    writePackedString(track.memo, at: 8, length: 36, in: &chunk)
    for (index, event) in events.enumerated() {
        let offset = rcpTrackHeaderSize + index * 4
        chunk[offset] = event.command
        chunk[offset + 1] = event.delay
        chunk[offset + 2] = event.param1
        chunk[offset + 3] = event.param2
    }
    return chunk
}

private func encodeSignedSevenBit(_ value: Int) -> UInt8 {
    let clamped = min(63, max(-64, value))
    if clamped < 0 {
        return UInt8(clamped + 0x80)
    }
    return UInt8(clamped)
}

private func writePackedString(_ text: String, at offset: Int, length: Int, in data: inout Data) {
    let encoded = text.data(using: .shiftJIS) ?? Data(text.utf8)
    let count = min(length, encoded.count)
    if count > 0 {
        data.replaceSubrange(offset..<(offset + count), with: encoded.prefix(count))
    }
}
