import AudioToolbox
import XCTest
@testable import STedPlayback

final class RealtimeMIDIOutputTests: XCTestCase {
    func testPanicSendsExplicitNoteOffsForActiveNotes() {
        let output = RealtimeMIDIOutput()
        var messages: [[UInt8]] = []
        output.bind { _, _, length, data in
            messages.append(Array(UnsafeBufferPointer(start: data, count: length)))
        }

        output.send([0x90, 60, 100])
        output.send([0x91, 64, 80])
        output.send([0x80, 60, 0])
        output.panic()

        XCTAssertEqual(messages.count, 3 + 16 * 2 + 1)
        XCTAssertEqual(messages.last, [0x81, 64, 0])
        XCTAssertFalse(messages.dropFirst(3).contains([0x80, 60, 0]))
        XCTAssertEqual(
            messages.filter { $0.count == 3 && $0[0] & 0xf0 == 0xb0 && $0[1] == 123 }.count,
            16
        )
        XCTAssertEqual(
            messages.filter { $0.count == 3 && $0[0] & 0xf0 == 0xb0 && $0[1] == 64 }.count,
            16
        )
    }

    func testPanicClearsActiveNoteState() {
        let output = RealtimeMIDIOutput()
        var messages: [[UInt8]] = []
        output.bind { _, _, length, data in
            messages.append(Array(UnsafeBufferPointer(start: data, count: length)))
        }

        output.send([0x90, 60, 100])
        output.panic()
        let countAfterFirstPanic = messages.count
        output.panic()

        XCTAssertEqual(messages.count, countAfterFirstPanic + 16 * 2)
    }

    func testPanicSuppressesLateMessagesUntilPlaybackBegins() {
        let output = RealtimeMIDIOutput()
        var messages: [[UInt8]] = []
        output.bind { _, _, length, data in
            messages.append(Array(UnsafeBufferPointer(start: data, count: length)))
        }

        output.panic()
        let countAfterPanic = messages.count
        output.send([0x90, 60, 100])
        XCTAssertEqual(messages.count, countAfterPanic)

        output.beginPlayback()
        output.send([0x90, 60, 100])
        XCTAssertEqual(messages.last, [0x90, 60, 100])
    }
}
