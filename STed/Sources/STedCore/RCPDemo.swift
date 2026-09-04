import Foundation

public enum RCPDemo {
    /// One middle-C quarter-note RCP used as a built-in audible check.
    public static let middleC: Data = makeRCP(trackEvents: [
        [60, 48, 36, 100],
        [0xfe, 0, 0, 0]
    ])

    /// Two-track phrase for sequencer UI: melody + bass.
    public static let phrase: Data = makeRCP(
        title: "Demo Phrase",
        tracks: [
            (1, 0, 0, "melody", [
                [60, 48, 36, 100],
                [64, 48, 36, 100],
                [67, 96, 72, 100],
                [0xfe, 0, 0, 0]
            ]),
            (2, 1, 0, "bass", [
                [48, 192, 180, 100],
                [0xfe, 0, 0, 0]
            ])
        ]
    )
}

func makeRCP(trackEvents: [[UInt8]]) -> Data {
    makeRCP(title: "", tracks: [(1, 0, 0, "", trackEvents)])
}

func makeRCP(
    title: String,
    tracks: [(number: UInt8, channel: UInt8, mode: UInt8, memo: String, events: [[UInt8]])]
) -> Data {
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
        chunk[1] = UInt8((trackLength >> 8) & 0xff)
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
