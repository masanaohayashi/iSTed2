import STedPlayback
import XCTest

final class AudioUnitCatalogTests: XCTestCase {
    func testSC55ComponentCodesMatchInstalledAUv3() {
        XCTAssertEqual(AudioUnitCatalog.fourCC("aumu"), 0x61756d75)
        XCTAssertEqual(AudioUnitCatalog.fourCC("Sc55"), 0x53633535)
        XCTAssertEqual(AudioUnitCatalog.fourCC("Rin2"), 0x52696e32)

        let description = AudioUnitCatalog.sc55Description
        XCTAssertEqual(description.componentType, AudioUnitCatalog.fourCC("aumu"))
        XCTAssertEqual(description.componentSubType, AudioUnitCatalog.fourCC("Sc55"))
        XCTAssertEqual(description.componentManufacturer, AudioUnitCatalog.fourCC("Rin2"))
        XCTAssertEqual(AudioUnitCatalog.fourCCString(AudioUnitCatalog.fourCC("aumu")), "aumu")
        XCTAssertEqual(AudioUnitCatalog.fourCCString(AudioUnitCatalog.fourCC("Sc55")), "Sc55")
        XCTAssertEqual(AudioUnitCatalog.fourCCString(AudioUnitCatalog.fourCC("Rin2")), "Rin2")
    }

    func testPicksSC55FromRin2InstrumentsByName() {
        let match = AudioUnitCatalog.matchSC55(
            among: [
                AudioUnitCatalog.ListedComponent(
                    name: "STUDIO-R: IFW3",
                    type: AudioUnitCatalog.fourCC("aumu"),
                    subtype: AudioUnitCatalog.fourCC("Ifw3"),
                    manufacturer: AudioUnitCatalog.fourCC("Rin2")
                ),
                AudioUnitCatalog.ListedComponent(
                    name: "STUDIO-R: SC-55",
                    type: AudioUnitCatalog.fourCC("aumu"),
                    subtype: AudioUnitCatalog.fourCC("Sc55"),
                    manufacturer: AudioUnitCatalog.fourCC("Rin2")
                )
            ]
        )
        XCTAssertEqual(match?.subtype, AudioUnitCatalog.fourCC("Sc55"))
        XCTAssertEqual(match?.name, "STUDIO-R: SC-55")
    }

    func testPicksUppercaseSC55Subtype() {
        let match = AudioUnitCatalog.matchSC55(
            among: [
                AudioUnitCatalog.ListedComponent(
                    name: "STUDIO-R: SC-55",
                    type: AudioUnitCatalog.fourCC("aumu"),
                    subtype: AudioUnitCatalog.fourCC("SC55"),
                    manufacturer: AudioUnitCatalog.fourCC("Rin2")
                )
            ]
        )
        XCTAssertEqual(match?.subtype, AudioUnitCatalog.fourCC("SC55"))
    }

    func testPicksSC55ByDisplayNameIfSubtypeDiffers() {
        let match = AudioUnitCatalog.matchSC55(
            among: [
                AudioUnitCatalog.ListedComponent(
                    name: "SC-55",
                    type: AudioUnitCatalog.fourCC("aumu"),
                    subtype: AudioUnitCatalog.fourCC("XXXX"),
                    manufacturer: AudioUnitCatalog.fourCC("Rin2")
                )
            ]
        )
        XCTAssertEqual(match?.subtype, AudioUnitCatalog.fourCC("XXXX"))
    }
}
