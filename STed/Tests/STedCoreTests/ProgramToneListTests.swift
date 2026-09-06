import XCTest
@testable import STedCore

final class ProgramToneListTests: XCTestCase {
    func testProgramNumbersMatchCapitalDefinition() {
        XCTAssertEqual(ProgramToneList.names.count, 128)
        XCTAssertEqual(ProgramToneList.names[0], "Piano 1")
        XCTAssertEqual(ProgramToneList.names[40], "Violin")
        XCTAssertTrue(ProgramToneList.names.allSatisfy { !$0.isEmpty })
    }

    func testNavigationWrapsAcrossPagesAndEnds() {
        XCTAssertEqual(ProgramToneList.moved(127, by: 1), 0)
        XCTAssertEqual(ProgramToneList.moved(0, by: -1), 127)
        XCTAssertEqual(ProgramToneList.moved(120, by: 16), 8)
        XCTAssertEqual(ProgramToneList.moved(8, by: -16), 120)
    }
}
